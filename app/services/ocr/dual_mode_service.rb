# app/services/ocr/dual_mode_service.rb
# Intelligent OCR service that selects between AWS Textract and Docling
# based on document characteristics, cost optimization, and availability

module Ocr
  class DualModeService
    include Singleton
    include ActiveSupport::Rescuable

    # Document types that benefit from Textract's specialized processing
    TEXTRACT_PREFERRED_TYPES = %w[
      invoice receipt form id passport
      check bank_statement tax_form medical_record
    ].freeze

    attr_reader :metrics

    def initialize
      @metrics = { provider: nil, fallback_used: false, processing_time: 0 }
    end

    # Main entry point for document processing
    def process_document(entity, file_path, options = {})
      start_time = Time.current

      # Determine which provider to use
      provider = determine_provider(file_path, options)
      @metrics[:provider] = provider
      @metrics[:entity_id] = entity&.id

      Rails.logger.info "OCR: Using #{provider} provider for #{File.basename(file_path)}"

      result = case provider
      when :textract
        process_with_textract(entity, file_path, options)
      when :docling
        process_with_docling(entity, file_path, options)
      when :auto
        process_with_auto_selection(entity, file_path, options)
      else
        raise ArgumentError, "Unknown OCR provider: #{provider}"
      end

      @metrics[:processing_time] = Time.current - start_time
      log_metrics(entity, file_path)

      # Run shadow mode if enabled (process with both for comparison)
      run_shadow_mode(entity, file_path, options) if shadow_mode_enabled?

      result
    rescue => e
      handle_processing_error(entity, e, file_path, options)
    end

    # Process with automatic provider selection
    def process_with_auto_selection(entity, file_path, options = {})
      document_type = detect_document_type(file_path, options)
      file_size_mb = File.size(file_path) / 1.megabyte.to_f

      # Decision logic for provider selection
      if should_use_textract?(document_type, file_size_mb, options)
        process_with_textract(entity, file_path, options)
      else
        process_with_docling(entity, file_path, options)
      end
    end

    # Process with AWS Textract
    def process_with_textract(entity, file_path, options = {})
      unless textract_available?
        Rails.logger.warn "Textract not available, falling back to Docling"
        @metrics[:fallback_used] = true
        return process_with_docling(entity, file_path, options)
      end

      service = Aws::TextractService.new(entity)
      result = service.process_document(file_path, options)

      # Enhance with Comprehend if enabled
      if comprehend_enabled? && result[:raw_text].present?
        enhance_with_comprehend(entity, result)
      end

      format_result(result, :textract)
    rescue Aws::TextractService::RetryableError => e
      Rails.logger.warn "Textract failed with retryable error: #{e.message}"

      if fallback_enabled?
        @metrics[:fallback_used] = true
        process_with_docling(entity, file_path, options)
      else
        raise
      end
    end

    # Process with Docling
    def process_with_docling(entity, file_path, options = {})
      unless docling_available?
        raise "Neither Textract nor Docling is available for OCR processing"
      end

      # Use existing Docling bridge service
      service = DoclingBridgeService.new

      # Determine chunking strategy
      chunking_strategy = options[:chunking_strategy] || 'semantic'
      chunk_size = options[:chunk_size] || 2000

      result = service.process_document(
        file_path,
        chunk_size: chunk_size,
        chunking_strategy: chunking_strategy,
        preserve_tables: options[:extract_tables] != false,
        extract_images: options[:extract_images] || false
      )

      format_result(result, :docling)
    rescue => e
      Rails.logger.error "Docling processing failed: #{e.message}"

      # If Docling fails and we haven't tried Textract yet, try it
      if textract_available? && fallback_enabled? && @metrics[:provider] != :textract
        @metrics[:fallback_used] = true
        process_with_textract(file_path, options)
      else
        raise
      end
    end

    # Compare results from both providers (for testing/optimization)
    def compare_providers(entity, file_path, options = {})
      results = {}
      timings = {}

      # Process with Textract
      if textract_available?
        start = Time.current
        begin
          results[:textract] = process_with_textract(entity, file_path, options.merge(skip_fallback: true))
          timings[:textract] = Time.current - start
        rescue => e
          results[:textract] = { error: e.message }
          timings[:textract] = Time.current - start
        end
      end

      # Process with Docling
      if docling_available?
        start = Time.current
        begin
          results[:docling] = process_with_docling(entity, file_path, options.merge(skip_fallback: true))
          timings[:docling] = Time.current - start
        rescue => e
          results[:docling] = { error: e.message }
          timings[:docling] = Time.current - start
        end
      end

      # Calculate similarity if both succeeded
      similarity = calculate_similarity(results) if results[:textract] && results[:docling]

      {
        results: results,
        timings: timings,
        similarity: similarity,
        recommendation: recommend_provider(results, timings, file_path)
      }
    end

    private

    def determine_provider(file_path, options)
      # Check if provider is explicitly specified
      return options[:provider].to_sym if options[:provider].present?

      # Use environment configuration
      configured_provider = ENV.fetch('OCR_PROVIDER', 'auto').downcase.to_sym

      # Override for testing
      return :auto if configured_provider == :auto

      configured_provider
    end

    def should_use_textract?(document_type, file_size_mb, options)
      # Always use Textract for specific document types
      if TEXTRACT_PREFERRED_TYPES.include?(document_type)
        return true
      end

      # Use Docling for small documents to save costs
      max_docling_size = ENV.fetch('OCR_DOCLING_MAX_SIZE_MB', '5').to_f
      if file_size_mb <= max_docling_size
        return false
      end

      # Use Textract for complex documents requiring high accuracy
      if options[:high_accuracy] || options[:extract_forms]
        return true
      end

      # Default to Textract for better accuracy on large documents
      true
    end

    def detect_document_type(file_path, options)
      # Check if type is provided
      return options[:document_type] if options[:document_type].present?

      # Detect from filename patterns
      filename = File.basename(file_path).downcase

      return 'invoice' if filename.include?('invoice')
      return 'receipt' if filename.include?('receipt')
      return 'form' if filename.include?('form') || filename.include?('application')
      return 'id' if filename.include?('license') || filename.include?('passport')
      return 'bank_statement' if filename.include?('statement')
      return 'contract' if filename.include?('contract') || filename.include?('agreement')

      # Default type
      'general'
    end

    def textract_available?
      return false unless ENV['TEXTRACT_ENABLED'] == 'true'
      return false unless ENV['AWS_ACCESS_KEY_ID'].present?

      # Check if the service class exists
      defined?(Aws::TextractService)
    end

    def docling_available?
      # Check if Docling bridge service is available
      defined?(DoclingBridgeService) && DoclingBridgeService.new.available?
    end

    def comprehend_enabled?
      ENV['COMPREHEND_ENABLED'] == 'true'
    end

    def fallback_enabled?
      ENV.fetch('OCR_FALLBACK_ENABLED', 'true') == 'true'
    end

    def shadow_mode_enabled?
      ENV['OCR_SHADOW_MODE'] == 'true'
    end

    def enhance_with_comprehend(entity, result)
      service = Aws::ComprehendService.instance
      analysis = service.analyze_document(result[:raw_text], entity: entity)

      result[:nlp_analysis] = {
        entities: analysis[:entities],
        key_phrases: analysis[:key_phrases],
        sentiment: analysis[:sentiment],
        language: analysis[:language]
      }

      result
    rescue => e
      Rails.logger.warn "Comprehend enhancement failed: #{e.message}"
      result
    end

    def format_result(raw_result, provider)
      # Standardize result format regardless of provider
      formatted = {
        provider: provider,
        pages: [],
        raw_text: '',
        tables: [],
        forms: [],
        metadata: {
          provider: provider,
          processed_at: Time.current
        }
      }

      case provider
      when :textract
        formatted[:pages] = raw_result[:pages] || []
        formatted[:raw_text] = raw_result[:raw_text] || ''
        formatted[:tables] = raw_result[:tables] || []
        formatted[:forms] = raw_result[:forms] || []
        formatted[:metadata].merge!(raw_result[:metadata] || {})

      when :docling
        # Convert Docling chunks to pages format
        if raw_result[:chunks].present?
          pages_by_number = {}

          raw_result[:chunks].each do |chunk|
            page_num = chunk.dig(:metadata, :page) || 1
            pages_by_number[page_num] ||= {
              page_number: page_num,
              text: '',
              lines: [],
              tables: []
            }

            pages_by_number[page_num][:text] += chunk[:content] + "\n"

            # Extract tables if present
            if chunk.dig(:metadata, :type) == 'table'
              pages_by_number[page_num][:tables] << {
                data: parse_table_from_content(chunk[:content]),
                confidence: 1.0
              }
            end
          end

          formatted[:pages] = pages_by_number.values.sort_by { |p| p[:page_number] }
          formatted[:raw_text] = formatted[:pages].map { |p| p[:text] }.join("\n")
        end

        formatted[:metadata].merge!(raw_result[:metadata] || {})
      end

      # Add NLP analysis if present
      formatted[:nlp_analysis] = raw_result[:nlp_analysis] if raw_result[:nlp_analysis].present?

      formatted
    end

    def parse_table_from_content(content)
      # Simple table parsing from markdown format
      lines = content.split("\n")
      table_data = []

      lines.each do |line|
        next if line.strip.empty? || line.include?('---')

        row = line.split('|').map(&:strip).reject(&:empty?)
        table_data << row unless row.empty?
      end

      table_data
    end

    def run_shadow_mode(entity, file_path, options)
      # Run comparison in background job to not block main processing
      OcrComparisonJob.perform_later(entity.id, file_path, options) if entity
    rescue => e
      Rails.logger.error "Shadow mode comparison failed: #{e.message}"
    end

    def calculate_similarity(results)
      return nil unless results[:textract][:raw_text] && results[:docling][:raw_text]

      # Simple character-based similarity
      text1 = results[:textract][:raw_text].downcase.gsub(/\s+/, ' ')
      text2 = results[:docling][:raw_text].downcase.gsub(/\s+/, ' ')

      return 1.0 if text1 == text2

      # Calculate Levenshtein distance-based similarity
      max_len = [text1.length, text2.length].max
      return 0.0 if max_len == 0

      distance = levenshtein_distance(text1, text2)
      similarity = 1.0 - (distance.to_f / max_len)

      similarity.round(3)
    end

    def levenshtein_distance(str1, str2)
      # Simple implementation - in production, use a gem like 'levenshtein-ffi'
      m = str1.length
      n = str2.length

      return n if m == 0
      return m if n == 0

      # For performance, truncate very long strings
      if m > 1000 || n > 1000
        str1 = str1[0...1000]
        str2 = str2[0...1000]
        m = str1.length
        n = str2.length
      end

      d = Array.new(m + 1) { Array.new(n + 1) }

      (0..m).each { |i| d[i][0] = i }
      (0..n).each { |j| d[0][j] = j }

      (1..m).each do |i|
        (1..n).each do |j|
          cost = str1[i - 1] == str2[j - 1] ? 0 : 1
          d[i][j] = [
            d[i - 1][j] + 1,      # deletion
            d[i][j - 1] + 1,      # insertion
            d[i - 1][j - 1] + cost # substitution
          ].min
        end
      end

      d[m][n]
    end

    def recommend_provider(results, timings, file_path)
      recommendations = []

      # Check success
      textract_success = results[:textract] && !results[:textract][:error]
      docling_success = results[:docling] && !results[:docling][:error]

      if textract_success && docling_success
        # Both succeeded - compare quality and speed
        if timings[:docling] < timings[:textract] * 0.5
          recommendations << "Docling is significantly faster (#{(timings[:textract] / timings[:docling]).round(1)}x)"
        end

        if results[:textract][:tables]&.any? && results[:docling][:tables]&.empty?
          recommendations << "Textract detected tables that Docling missed"
        end

        if results[:textract][:forms]&.any?
          recommendations << "Textract extracted form fields"
        end
      elsif textract_success
        recommendations << "Only Textract succeeded"
      elsif docling_success
        recommendations << "Only Docling succeeded"
      else
        recommendations << "Both providers failed"
      end

      # Cost consideration
      file_size_mb = File.size(file_path) / 1.megabyte.to_f
      if file_size_mb < 5
        recommendations << "Consider Docling for cost savings on small documents"
      end

      recommendations.join('; ')
    end

    def handle_processing_error(entity, error, file_path, options)
      Rails.logger.error "OCR processing failed for #{file_path}: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")

      # Try fallback if not already attempted
      if fallback_enabled? && !@metrics[:fallback_used]
        @metrics[:fallback_used] = true

        # Try the other provider
        if @metrics[:provider] == :textract
          Rails.logger.info "Falling back to Docling"
          return process_with_docling(entity, file_path, options)
        elsif @metrics[:provider] == :docling
          Rails.logger.info "Falling back to Textract"
          return process_with_textract(entity, file_path, options)
        end
      end

      # Re-raise if no fallback available
      raise error
    end

    def log_metrics(entity, file_path)
      Rails.logger.info "OCR Metrics: #{@metrics.to_json}"

      # Track in database if entity has metrics tracking enabled
      if entity && entity.respond_to?(:track_ocr_metrics?) && entity.track_ocr_metrics?
        OcrMetric.create!(
          entity: entity,
          file_path: file_path,
          provider: @metrics[:provider],
          fallback_used: @metrics[:fallback_used],
          processing_time_ms: (@metrics[:processing_time] * 1000).to_i,
          status: 'success'
        )
      end
    rescue => e
      Rails.logger.warn "Failed to log OCR metrics: #{e.message}"
    end
  end
end