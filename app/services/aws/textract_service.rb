# app/services/aws/textract_service.rb
require 'aws-sdk-textract'
require 'aws-sdk-s3'

module Aws
  class TextractService
    include Singleton
    include ActiveSupport::Rescuable

    SUPPORTED_FORMATS = %w[pdf png jpg jpeg tiff].freeze
    MAX_SYNC_PAGES = 1  # Use async for multi-page docs
    MAX_FILE_SIZE = 500.megabytes # Textract limit

    attr_reader :client, :s3_client

    def initialize
      @client = ::Aws::Textract::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1'),
        http_read_timeout: 120
      )
      @s3_client = ::Aws::S3::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1')
      )
    rescue ::Aws::Errors::MissingCredentialsError => e
      ::Rails.logger.error "AWS credentials not configured: #{e.message}"
      raise "AWS credentials not configured. Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
    end

    # Main entry point for document processing
    def process_document(entity, file_path, options = {})
      validate_file!(file_path)

      # Upload to S3 first (Textract requires S3 location)
      s3_key = upload_to_s3(entity, file_path)

      # Determine processing method
      if single_page_document?(file_path)
        result = process_sync(s3_key, options)
      else
        result = process_async(entity, s3_key, options)
      end

      # Cleanup S3 file unless specified otherwise
      cleanup_s3_file(s3_key) if options[:cleanup] != false

      result
    rescue ::Aws::Textract::Errors::ServiceError => e
      handle_textract_error(e)
    end

    # Synchronous processing for single-page documents
    def process_sync(s3_key, options = {})
      features = determine_features(options)

      ::Rails.logger.info "Processing document synchronously with features: #{features.join(', ')}"

      response = @client.analyze_document(
        document: {
          s3_object: {
            bucket: bucket_name,
            name: s3_key
          }
        },
        feature_types: features
      )

      parse_response(response, options)
    end

    # Asynchronous processing for multi-page documents
    def process_async(entity, s3_key, options = {})
      features = determine_features(options)

      ::Rails.logger.info "Starting async document analysis with features: #{features.join(', ')}"

      # Start async job
      params = {
        document_location: {
          s3_object: {
            bucket: bucket_name,
            name: s3_key
          }
        },
        feature_types: features
      }
      params[:notification_channel] = notification_config if notification_enabled?

      job_response = @client.start_document_analysis(params)

      # Queue background job to check results
      TextractResultJob.perform_later(
        entity_id: entity.id,
        job_id: job_response.job_id,
        s3_key: s3_key,
        options: options
      )

      {
        status: 'processing',
        job_id: job_response.job_id,
        message: 'Document analysis started. Results will be available soon.',
        estimated_time_seconds: estimate_processing_time(s3_key)
      }
    end

    # Get results from async job
    def get_job_results(job_id)
      response = @client.get_document_analysis(job_id: job_id)

      case response.job_status
      when 'SUCCEEDED'
        results = parse_response(response)

        # Get all pages if paginated
        while response.next_token
          response = @client.get_document_analysis(
            job_id: job_id,
            next_token: response.next_token
          )
          merge_response_pages(results, parse_response(response))
        end

        results[:status] = 'completed'
        results
      when 'IN_PROGRESS'
        {
          status: 'processing',
          progress: response.progress_percentage || 0,
          message: "Processing... #{response.progress_percentage}% complete"
        }
      when 'FAILED'
        {
          status: 'failed',
          error: response.status_message || 'Document analysis failed'
        }
      else
        {
          status: response.job_status.downcase
        }
      end
    end

    # Extract tables specifically
    def extract_tables(s3_key)
      response = @client.analyze_document(
        document: { s3_object: { bucket: bucket_name, name: s3_key } },
        feature_types: ['TABLES']
      )

      parse_tables(response)
    end

    # Extract forms specifically
    def extract_forms(s3_key)
      response = @client.analyze_document(
        document: { s3_object: { bucket: bucket_name, name: s3_key } },
        feature_types: ['FORMS']
      )

      parse_forms(response)
    end

    # Analyze expense documents (invoices, receipts)
    def analyze_expense(entity, file_path, options = {})
      validate_file!(file_path)
      s3_key = upload_to_s3(entity, file_path)

      response = @client.analyze_expense(
        document: {
          s3_object: {
            bucket: bucket_name,
            name: s3_key
          }
        }
      )

      parse_expense_response(response)
    ensure
      cleanup_s3_file(s3_key) if s3_key && options[:cleanup] != false
    end

    # Analyze identity documents (driver's license, passport)
    def analyze_identity(entity, file_path, options = {})
      validate_file!(file_path)
      s3_key = upload_to_s3(entity, file_path)

      response = @client.analyze_id(
        document_pages: [
          {
            s3_object: {
              bucket: bucket_name,
              name: s3_key
            }
          }
        ]
      )

      parse_identity_response(response)
    ensure
      cleanup_s3_file(s3_key) if s3_key && options[:cleanup] != false
    end

    private

    def bucket_name
      @bucket_name ||= ENV.fetch('RAG_BUCKET', "agent-marketing-rag-storage")
    end

    def upload_to_s3(entity, file_path)
      file_name = File.basename(file_path)
      s3_key = "textract/#{entity.id}/#{SecureRandom.hex(8)}/#{file_name}"

      ::Rails.logger.info "Uploading file to S3: s3://#{bucket_name}/#{s3_key}"

      File.open(file_path, 'rb') do |file|
        @s3_client.put_object(
          bucket: bucket_name,
          key: s3_key,
          body: file,
          metadata: {
            'entity-id' => entity.id.to_s,
            'uploaded-at' => Time.current.iso8601,
            'original-filename' => file_name
          }
        )
      end

      s3_key
    rescue ::Aws::S3::Errors::ServiceError => e
      ::Rails.logger.error "S3 upload failed: #{e.message}"
      raise "Failed to upload file to S3: #{e.message}"
    end

    def cleanup_s3_file(s3_key)
      @s3_client.delete_object(bucket: bucket_name, key: s3_key)
      ::Rails.logger.info "Cleaned up S3 file: #{s3_key}"
    rescue => e
      ::Rails.logger.warn "Failed to cleanup S3 file #{s3_key}: #{e.message}"
    end

    def parse_tables(response)
      tables = []
      block_map = response.blocks.index_by(&:id)

      response.blocks.each do |block|
        next unless block.block_type == 'TABLE'
        table = parse_table_block(block, block_map)
        tables << table if table
      end

      tables
    end

    def parse_forms(response)
      forms = []
      block_map = response.blocks.index_by(&:id)

      response.blocks.each do |block|
        next unless block.block_type == 'KEY_VALUE_SET'
        next unless block.entity_types&.include?('KEY')

        form_field = parse_form_field(block, block_map)
        forms << form_field if form_field
      end

      forms
    end

    def determine_features(options)
      features = []
      features << 'TABLES' if options[:extract_tables] != false
      features << 'FORMS' if options[:extract_forms]
      features << 'LAYOUT' if options[:extract_layout] != false  # Default to true like TABLES
      features << 'SIGNATURES' if options[:detect_signatures]
      features << 'QUERIES' if options[:queries].present?

      # Default to tables and layout if no features specified
      features = ['TABLES', 'LAYOUT'] if features.empty?

      features
    end

    def parse_response(response, options = {})
      result = {
        pages: [],
        tables: [],
        forms: [],
        raw_text: '',
        metadata: extract_metadata(response)
      }

      # Group blocks by page
      blocks_by_page = response.blocks.group_by { |b| b.page || 1 }

      blocks_by_page.each do |page_num, blocks|
        page_data = {
          page_number: page_num,
          text: '',
          lines: [],
          tables: [],
          forms: [],
          confidence_scores: []
        }

        # Build block lookup map for relationships
        block_map = blocks.index_by(&:id)

        blocks.each do |block|
          case block.block_type
          when 'PAGE'
            page_data[:confidence] = block.confidence
            page_data[:geometry] = parse_geometry(block.geometry)

          when 'LINE'
            line_text = block.text || ''
            page_data[:lines] << {
              text: line_text,
              confidence: block.confidence,
              geometry: parse_geometry(block.geometry)
            }
            page_data[:text] += "#{line_text}\n"
            page_data[:confidence_scores] << block.confidence if block.confidence

          when 'TABLE'
            if options[:extract_tables] != false
              table = parse_table_block(block, block_map)
              page_data[:tables] << table if table
            end

          when 'KEY_VALUE_SET'
            if block.entity_types&.include?('KEY') && options[:extract_forms] != false
              form_field = parse_form_field(block, block_map)
              page_data[:forms] << form_field if form_field
            end

          when 'QUERY'
            if block.query
              page_data[:queries] ||= []
              page_data[:queries] << {
                text: block.query.text,
                answer: block.query.answer,
                confidence: block.confidence
              }
            end
          end
        end

        # Calculate average confidence for the page
        if page_data[:confidence_scores].any?
          page_data[:average_confidence] = (page_data[:confidence_scores].sum / page_data[:confidence_scores].count).round(3)
        end

        result[:pages] << page_data
        result[:raw_text] += page_data[:text]
        result[:tables].concat(page_data[:tables])
        result[:forms].concat(page_data[:forms])
      end

      result
    end

    def parse_table_block(table_block, block_map)
      cells = []

      # Extract cells from relationships
      table_block.relationships&.each do |relationship|
        next unless relationship.type == 'CHILD'

        relationship.ids.each do |cell_id|
          cell_block = block_map[cell_id]
          next unless cell_block&.block_type == 'CELL'

          cells << {
            row: cell_block.row_index,
            column: cell_block.column_index,
            text: extract_cell_text(cell_block, block_map),
            confidence: cell_block.confidence,
            row_span: cell_block.row_span || 1,
            column_span: cell_block.column_span || 1
          }
        end
      end

      return nil if cells.empty?

      # Convert to 2D array
      max_row = cells.map { |c| c[:row] }.compact.max || 0
      max_col = cells.map { |c| c[:column] }.compact.max || 0

      table_data = Array.new(max_row) { Array.new(max_col, '') }

      cells.each do |cell|
        next unless cell[:row] && cell[:column]
        table_data[cell[:row] - 1][cell[:column] - 1] = cell[:text]
      end

      {
        data: table_data,
        confidence: table_block.confidence,
        geometry: parse_geometry(table_block.geometry),
        cell_count: cells.size,
        rows: max_row,
        columns: max_col
      }
    end

    def extract_cell_text(cell_block, block_map)
      text_parts = []

      cell_block.relationships&.each do |relationship|
        next unless relationship.type == 'CHILD'

        relationship.ids.each do |child_id|
          child_block = block_map[child_id]
          text_parts << child_block.text if child_block&.text
        end
      end

      text_parts.join(' ').strip
    end

    def parse_form_field(key_block, block_map)
      # Find the key text
      key_text = extract_relationship_text(key_block, block_map, 'CHILD')

      # Find the value
      value_text = nil
      key_block.relationships&.each do |relationship|
        next unless relationship.type == 'VALUE'

        relationship.ids.each do |value_id|
          value_block = block_map[value_id]
          if value_block
            value_text = extract_relationship_text(value_block, block_map, 'CHILD')
          end
        end
      end

      return nil unless key_text.present?

      {
        key: key_text.strip,
        value: value_text&.strip || '',
        confidence: key_block.confidence,
        geometry: parse_geometry(key_block.geometry)
      }
    end

    def extract_relationship_text(block, block_map, relationship_type)
      text_parts = []

      block.relationships&.each do |relationship|
        next unless relationship.type == relationship_type

        relationship.ids.each do |child_id|
          child_block = block_map[child_id]
          text_parts << child_block.text if child_block&.text
        end
      end

      text_parts.join(' ')
    end

    def parse_expense_response(response)
      expenses = []

      response.expense_documents.each do |doc|
        expense = {
          summary_fields: {},
          line_items: []
        }

        # Parse summary fields
        doc.summary_fields.each do |field|
          if field.type && field.value_detection
            expense[:summary_fields][field.type.text] = {
              value: field.value_detection.text,
              confidence: field.value_detection.confidence
            }
          end
        end

        # Parse line items
        doc.line_item_groups.each do |group|
          group.line_items.each do |item|
            line_item = {}
            item.line_item_expense_fields.each do |field|
              if field.type && field.value_detection
                line_item[field.type.text] = {
                  value: field.value_detection.text,
                  confidence: field.value_detection.confidence
                }
              end
            end
            expense[:line_items] << line_item if line_item.any?
          end
        end

        expenses << expense
      end

      {
        expenses: expenses,
        metadata: {
          analyzed_at: Time.current,
          document_type: 'expense'
        }
      }
    end

    def parse_identity_response(response)
      identity_documents = []

      response.identity_documents.each do |doc|
        identity = {
          fields: {},
          document_type: nil
        }

        doc.identity_document_fields.each do |field|
          if field.type && field.value_detection
            field_name = field.type.text
            identity[:fields][field_name] = {
              value: field.value_detection.text,
              confidence: field.value_detection.confidence
            }

            # Detect document type from fields
            if field_name == 'DOCUMENT_TYPE'
              identity[:document_type] = field.value_detection.text
            end
          end
        end

        identity_documents << identity
      end

      {
        identity_documents: identity_documents,
        metadata: {
          analyzed_at: Time.current,
          document_type: 'identity'
        }
      }
    end

    def parse_geometry(geometry)
      return nil unless geometry

      {
        bounding_box: {
          width: geometry.bounding_box&.width,
          height: geometry.bounding_box&.height,
          left: geometry.bounding_box&.left,
          top: geometry.bounding_box&.top
        },
        polygon: geometry.polygon&.map { |point| { x: point.x, y: point.y } }
      }
    end

    def extract_metadata(response)
      {
        pages: response.document_metadata&.pages || 1,
        job_status: response.job_status,
        job_id: response.job_id,
        analyzed_at: Time.current,
        textract_version: response.analyze_document_model_version,
        warnings: response.warnings
      }
    end

    def merge_response_pages(results, new_pages)
      results[:pages].concat(new_pages[:pages])
      results[:raw_text] += new_pages[:raw_text]
      results[:tables].concat(new_pages[:tables])
      results[:forms].concat(new_pages[:forms])
    end

    def single_page_document?(file_path)
      # For images, always single page
      return true if %w[png jpg jpeg tiff].include?(File.extname(file_path).downcase.delete('.'))

      # For PDFs, check page count (would need a PDF library in production)
      # For now, assume multi-page for all PDFs
      false
    end

    def estimate_processing_time(s3_key)
      # Estimate based on file size
      begin
        object = @s3_client.head_object(bucket: bucket_name, key: s3_key)
        file_size_mb = object.content_length / 1.megabyte.to_f

        # Rough estimate: 2 seconds per MB
        (file_size_mb * 2).round
      rescue
        30 # Default estimate
      end
    end

    def validate_file!(file_path)
      raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

      extension = File.extname(file_path).downcase.delete('.')
      unless SUPPORTED_FORMATS.include?(extension)
        raise ArgumentError, "Unsupported file format: #{extension}. Supported formats: #{SUPPORTED_FORMATS.join(', ')}"
      end

      # Check file size
      if File.size(file_path) > MAX_FILE_SIZE
        raise ArgumentError, "File too large: #{File.size(file_path)} bytes (max: #{MAX_FILE_SIZE} bytes)"
      end
    end

    def notification_enabled?
      ENV['TEXTRACT_SNS_TOPIC_ARN'].present?
    end

    def notification_config
      return nil unless notification_enabled?

      {
        sns_topic_arn: ENV['TEXTRACT_SNS_TOPIC_ARN'],
        role_arn: ENV['TEXTRACT_ROLE_ARN']
      }
    end

    def handle_textract_error(error)
      case error
      when ::Aws::Textract::Errors::ThrottlingException
        raise RetryableError, "Textract rate limit reached. Please retry."
      when ::Aws::Textract::Errors::ProvisionedThroughputExceededException
        raise RetryableError, "Textract throughput exceeded. Please retry."
      when ::Aws::Textract::Errors::InvalidS3ObjectException
        raise ArgumentError, "Invalid S3 object: #{error.message}"
      when ::Aws::Textract::Errors::DocumentTooLargeException
        raise ArgumentError, "Document too large for Textract processing"
      when ::Aws::Textract::Errors::BadDocumentException
        raise ArgumentError, "Document is malformed or corrupted"
      when ::Aws::Textract::Errors::AccessDeniedException
        raise "Access denied to Textract. Check AWS permissions."
      else
        ::Rails.logger.error "Textract error: #{error.class} - #{error.message}"
        raise error
      end
    end

    class RetryableError < StandardError; end
  end
end