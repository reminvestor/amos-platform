module Scout
  class DocumentProcessor
    def initialize(entity:, user:, session_id: nil, url_generator: nil)
      @entity = entity
      @user = user
      @session_id = session_id
      @url_generator = url_generator
    end

    def self.document_file?(extension)
      DoclingBridgeService::SUPPORTED_EXTENSIONS.include?(extension)
    end

    def process_for_rag(file, storage_type: 'long-term', ocr_provider: nil)
      Rails.logger.info "📄 Processing document for RAG: #{file.original_filename} (storage: #{storage_type})"

      # Save uploaded file temporarily
      temp_file = Tempfile.new([File.basename(file.original_filename, ".*"), File.extname(file.original_filename)])
      temp_file.binmode
      temp_file.write(file.read)
      temp_file.rewind
      temp_path = temp_file.path

      # Rewind the original file for Active Storage attachment
      file.rewind if file.respond_to?(:rewind)

      begin
        # Also create ImageAsset for storage (so file is accessible)
        image_asset = create_image_asset(file)

        # Process with dual-mode OCR service
        processing_result = if dual_mode_ocr_available?
          # Use new dual-mode OCR service (Textract + Docling)
          ocr_service = Ocr::DualModeService.instance
          ocr_result = ocr_service.process_document(temp_path, {
            provider: ocr_provider,
            document_type: detect_document_type(file.original_filename),
            extract_tables: true,
            extract_forms: true,
            create_chunks: true
          })

          # Convert to expected format
          {
            success: true,
            chunks: format_ocr_chunks(ocr_result),
            metadata: ocr_result[:metadata],
            provider: ocr_result[:provider]
          }
        else
          # Fallback to original Docling-only processor
          processor = DocumentProcessorService.new(use_docling: true)
          processor.process_documents([{
            type: "file",
            content: temp_path,
            filename: file.original_filename
          }])
        end

        unless processing_result[:success]
          return {
            success: false,
            error: processing_result[:error] || "Document processing failed"
          }
        end

        # Calculate file hash for deduplication
        file_hash = Digest::SHA256.hexdigest(File.read(temp_path))

        if storage_type == 'short-term'
          store_in_redis(file, image_asset, file_hash, processing_result)
        else
          store_in_database(file, image_asset, file_hash, processing_result)
        end

      rescue => e
        Rails.logger.error "RAG processing error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        {
          success: false,
          error: e.message
        }
      ensure
        # Clean up temp file
        temp_file&.close
        temp_file&.unlink
      end
    end

    def create_image_asset(file)
      ImageAsset.create!(
        entity: @entity,
        user: @user,
        title: file.original_filename,
        file: file,
        source: "upload"
      )
    end

    def build_image_asset_response(image_asset, file)
      {
        url: asset_url(image_asset),
        filename: file.original_filename,
        content_type: file.content_type,
        size: file.size,
        asset_id: image_asset.id
      }
    end

    private

    attr_reader :entity, :user, :session_id, :url_generator

    def store_in_redis(file, image_asset, file_hash, processing_result)
      # Store in Redis for session-only access
      session_key = "rag:session:#{session_id}:documents"
      document_data = {
        filename: file.original_filename,
        file_hash: file_hash,
        page_count: processing_result.dig(:metadata, file.original_filename, :total_pages),
        chunks: processing_result[:chunks].map.with_index do |chunk, index|
          {
            content: chunk[:content],
            index: index,
            type: chunk.dig(:metadata, :type) || "text"
          }
        end,
        uploaded_at: Time.current.iso8601,
        asset_id: image_asset.id,
        asset_url: asset_url(image_asset)
      }

      # Store in Redis with 24 hour TTL
      Rails.logger.info "💾 Storing document in Redis with key: #{session_key}"
      $redis.hset(session_key, file.original_filename, document_data.to_json)
      $redis.expire(session_key, 24.hours.to_i)

      chunks_created = processing_result[:chunks].length
      Rails.logger.info "✅ Stored document '#{file.original_filename}' in Redis (session: #{session_id}, key: #{session_key}) with #{chunks_created} chunks"

      {
        success: true,
        url: asset_url(image_asset),
        asset_id: image_asset.id,
        chunks_count: chunks_created,
        processor: processing_result.dig(:metadata, file.original_filename, :processor) || "docling",
        storage_type: 'short-term'
      }
    end

    def store_in_database(file, image_asset, file_hash, processing_result)
      # Long-term storage in database
      rag_store = RagStore.create!(
        entity: entity,
        name: "Upload: #{file.original_filename}",
        app_name: "Scout Upload - #{Time.current.strftime('%Y-%m-%d %H:%M')}",
        store_type: "entity",
        pinecone_index: "amos-rag-#{Rails.env}",
        pinecone_namespace: "entity_#{entity.id}_#{SecureRandom.hex(4)}",
        processing_method: processing_result.dig(:metadata, file.original_filename, :processor) || "docling",
        processing_time_ms: processing_result.dig(:metadata, file.original_filename, :processing_time_ms)
      )

      # Merge asset_id into docling_metadata
      metadata = (processing_result.dig(:metadata, file.original_filename) || {}).merge(
        asset_id: image_asset.id,
        asset_url: asset_url(image_asset)
      )

      rag_document = RagDocument.create!(
        rag_store: rag_store,
        original_filename: file.original_filename,
        file_hash: file_hash,
        page_count: processing_result.dig(:metadata, file.original_filename, :total_pages),
        docling_metadata: metadata
      )

      chunks_created = 0
      processing_result[:chunks].each_with_index do |chunk, index|
        RagChunk.create!(
          rag_document: rag_document,
          content: chunk[:content],
          chunk_index: index,
          chunk_type: chunk.dig(:metadata, :type) || "text"
        )
        chunks_created += 1
      end

      Rails.logger.info "✅ Created RagStore ##{rag_store.id} with #{chunks_created} chunks"

      # Enqueue embedding generation job for all chunks
      if chunks_created > 0
        chunk_ids = rag_document.rag_chunks.pluck(:id)
        Rails.logger.info "📊 Enqueuing embedding job for #{chunk_ids.length} chunks"

        # Enqueue EmbeddingBatchJob to generate embeddings (job gets store from chunks)
        Rag::EmbeddingBatchJob.perform_later(chunk_ids)
      end

      {
        success: true,
        url: asset_url(image_asset),
        asset_id: image_asset.id,
        rag_store_id: rag_store.id,
        rag_document_id: rag_document.id,
        chunks_count: chunks_created,
        processor: rag_store.processing_method,
        storage_type: 'long-term'
      }
    end

    def asset_url(image_asset)
      if url_generator
        url_generator.call(image_asset.file)
      else
        # Fallback to Rails.application.routes.url_helpers if no generator provided
        Rails.application.routes.url_helpers.rails_blob_url(image_asset.file)
      end
    end

    private

    def dual_mode_ocr_available?
      defined?(Ocr::DualModeService) &&
        (ENV['OCR_PROVIDER'].present? || ENV['TEXTRACT_ENABLED'] == 'true')
    end

    def detect_document_type(filename)
      filename_lower = filename.downcase

      return 'invoice' if filename_lower.include?('invoice')
      return 'receipt' if filename_lower.include?('receipt')
      return 'contract' if filename_lower.include?('contract') || filename_lower.include?('agreement')
      return 'form' if filename_lower.include?('form') || filename_lower.include?('application')
      return 'id' if filename_lower.include?('license') || filename_lower.include?('passport') || filename_lower.include?('id')
      return 'statement' if filename_lower.include?('statement')
      return 'report' if filename_lower.include?('report')

      'general'
    end

    def format_ocr_chunks(ocr_result)
      chunks = []

      # Convert pages to chunks format
      ocr_result[:pages].each_with_index do |page, index|
        chunks << {
          content: page[:text],
          metadata: {
            type: 'page',
            page_number: page[:page_number],
            confidence: page[:confidence] || page[:average_confidence],
            provider: ocr_result[:provider]
          }
        }

        # Add table chunks if present
        page[:tables]&.each_with_index do |table, table_index|
          chunks << {
            content: format_table_for_chunk(table),
            metadata: {
              type: 'table',
              page_number: page[:page_number],
              table_index: table_index,
              provider: ocr_result[:provider]
            }
          }
        end

        # Add form chunks if present
        if page[:forms].present? && page[:forms].any?
          chunks << {
            content: format_forms_for_chunk(page[:forms]),
            metadata: {
              type: 'form',
              page_number: page[:page_number],
              provider: ocr_result[:provider]
            }
          }
        end
      end

      chunks
    end

    def format_table_for_chunk(table)
      return "" unless table[:data].present?

      lines = []
      table[:data].each_with_index do |row, i|
        lines << row.join(' | ')
      end
      lines.join("\n")
    end

    def format_forms_for_chunk(forms)
      forms.map { |field| "#{field[:key]}: #{field[:value]}" }.join("\n")
    end
  end
end
