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

    def process_for_rag(file, storage_type: 'long-term')
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

        # Process with DocumentProcessorService (which uses Docling)
        processor = DocumentProcessorService.new(use_docling: true)
        processing_result = processor.process_documents([{
          type: "file",
          content: temp_path,
          filename: file.original_filename
        }])

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
  end
end
