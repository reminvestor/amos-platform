# frozen_string_literal: true

module Tools
  class ParseCsvTool < BaseTool
    require 'csv'

    def self.metadata
      {
        name: "parse_csv",
        description: "Parse a CSV file from an upload or URL. Returns the data as structured records ready for import.",
        category: "data",
        input_schema: {
          type: "object",
          properties: {
            source: {
              type: "string",
              description: "Source of the CSV: 'upload' for recently uploaded file, 'url' for remote file, or 'text' for raw CSV content"
            },
            file_identifier: {
              type: "string",
              description: "For 'upload': the filename or document ID. For 'url': the full URL. For 'text': the raw CSV content."
            },
            has_headers: {
              type: "boolean",
              description: "Whether the first row contains column headers (default: true)"
            },
            preview_only: {
              type: "boolean",
              description: "If true, only return first 5 rows as preview (default: false)"
            },
            delimiter: {
              type: "string",
              description: "Column delimiter (default: comma). Options: 'comma', 'tab', 'semicolon', 'pipe'"
            }
          },
          required: ["source", "file_identifier"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      source = get_arg(args, :source)
      file_identifier = get_arg(args, :file_identifier)
      has_headers = get_arg(args, :has_headers, true)
      preview_only = get_arg(args, :preview_only, false)
      delimiter = get_arg(args, :delimiter, 'comma')

      if error = validate_required_args(args, [:source, :file_identifier])
        return error
      end

      # Get the CSV content
      csv_content = case source
      when 'upload'
        fetch_uploaded_file(file_identifier)
      when 'url'
        fetch_from_url(file_identifier)
      when 'text'
        file_identifier
      else
        return error_response("Invalid source type: #{source}. Use 'upload', 'url', or 'text'.")
      end

      return csv_content if csv_content.is_a?(Hash) && csv_content[:success] == false

      # Parse the CSV
      delimiter_char = case delimiter
      when 'tab' then "\t"
      when 'semicolon' then ";"
      when 'pipe' then "|"
      else ","
      end

      begin
        parsed = CSV.parse(csv_content, col_sep: delimiter_char)
        
        if parsed.empty?
          return error_response("CSV is empty or could not be parsed.")
        end

        # Extract headers and data
        if has_headers
          headers = parsed.first.map { |h| normalize_header(h) }
          data_rows = parsed[1..]
        else
          # Generate generic headers
          headers = parsed.first.each_with_index.map { |_, i| "column_#{i + 1}" }
          data_rows = parsed
        end

        # Convert to array of hashes
        records = data_rows.map do |row|
          headers.each_with_index.to_h do |header, idx|
            [header, row[idx]&.strip]
          end
        end

        # Apply preview limit if requested
        display_records = preview_only ? records.first(5) : records
        truncated = preview_only && records.length > 5

        # Detect field types for import guidance
        field_analysis = analyze_fields(headers, records.first(20))

        success_response(
          parsed: true,
          source: source,
          total_rows: records.length,
          columns: headers,
          field_analysis: field_analysis,
          records: display_records,
          truncated: truncated,
          import_ready: true,
          suggested_object_types: suggest_object_types(headers),
          message: "Successfully parsed #{records.length} rows with #{headers.length} columns.#{truncated ? ' Showing first 5 rows.' : ''}"
        )

      rescue CSV::MalformedCSVError => e
        error_response("CSV parsing error: #{e.message}. Try a different delimiter.")
      rescue => e
        Rails.logger.error "CSV parsing failed: #{e.message}"
        error_response("Failed to parse CSV: #{e.message}")
      end
    end

    private

    def fetch_uploaded_file(identifier)
      # Try to find in recent uploads or RAG documents
      # Check session documents first
      session_key = "uploads:#{user&.id || 'anonymous'}"
      
      # Try RAG documents - SORT BY MOST RECENT FIRST to avoid returning old documents
      all_docs = entity&.rag_stores&.flat_map(&:rag_documents)&.sort_by { |d| -(d.created_at&.to_i || 0) } || []
      
      # Prefer exact filename match, then fall back to partial match
      doc = all_docs.find { |d| d.original_filename&.downcase == identifier.downcase } ||
            all_docs.find do |d|
              d.original_filename&.downcase&.include?(identifier.downcase) ||
              d.title&.downcase&.include?(identifier.downcase)
            end

      if doc
        # Get content from docling metadata or chunks
        content = doc.docling_metadata&.dig('extracted_text')
        return content if content.present?
        
        # Try to read from S3 if available
        if doc.respond_to?(:s3_key) && doc.s3_key.present?
          return fetch_from_s3(doc.s3_key)
        end
      end

      # Check for ActiveStorage attachment
      if defined?(ActiveStorage::Blob)
        blob = ActiveStorage::Blob.find_by("filename ILIKE ?", "%#{identifier}%")
        if blob
          return blob.download
        end
      end

      error_response("Could not find uploaded file: #{identifier}. Make sure the file was recently uploaded.")
    end

    def fetch_from_url(url)
      require 'net/http'
      require 'uri'

      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        response.body
      else
        error_response("Failed to fetch CSV from URL: HTTP #{response.code}")
      end
    rescue URI::InvalidURIError
      error_response("Invalid URL: #{url}")
    rescue => e
      error_response("Failed to fetch URL: #{e.message}")
    end

    def fetch_from_s3(s3_key)
      # Placeholder for S3 fetching
      error_response("S3 fetching not implemented. Use the file content directly.")
    end

    def normalize_header(header)
      return "column" if header.blank?
      header.to_s.strip.downcase.gsub(/\s+/, '_').gsub(/[^a-z0-9_]/, '')
    end

    def analyze_fields(headers, sample_rows)
      headers.map do |header|
        values = sample_rows.map { |r| r[header] }.compact
        
        {
          name: header,
          detected_type: detect_type(values),
          sample_values: values.first(3),
          empty_count: sample_rows.count { |r| r[header].blank? },
          unique_count: values.uniq.length
        }
      end
    end

    def detect_type(values)
      return 'unknown' if values.empty?

      # Check if all values match certain patterns
      if values.all? { |v| v =~ /^\d+$/ }
        'integer'
      elsif values.all? { |v| v =~ /^\d+\.?\d*$/ }
        'decimal'
      elsif values.all? { |v| v =~ /^[\w.+-]+@[\w.-]+\.\w+$/ }
        'email'
      elsif values.all? { |v| v =~ /^\+?[\d\s\-().]+$/ && v.gsub(/\D/, '').length >= 7 }
        'phone'
      elsif values.all? { |v| v =~ /^\d{4}-\d{2}-\d{2}/ || v =~ /^\d{1,2}\/\d{1,2}\/\d{2,4}/ }
        'date'
      elsif values.all? { |v| %w[true false yes no 1 0].include?(v.downcase) }
        'boolean'
      elsif values.any? { |v| v.to_s.length > 100 }
        'text'
      else
        'string'
      end
    end

    def suggest_object_types(headers)
      suggestions = []
      
      header_set = headers.map(&:downcase).to_set

      # Check for contact-like data
      if (header_set & %w[email name first_name last_name phone]).any?
        suggestions << { type: 'contacts', confidence: 'high', reason: 'Contains email/name/phone fields' }
      end

      # Check for campaign-like data
      if (header_set & %w[campaign name status start_date end_date]).size >= 2
        suggestions << { type: 'campaigns', confidence: 'medium', reason: 'Contains campaign-like fields' }
      end

      # Check for transaction/order data
      if (header_set & %w[amount total price order_id invoice]).any?
        suggestions << { type: 'transactions', confidence: 'medium', reason: 'Contains financial fields' }
      end

      # Default suggestion
      if suggestions.empty?
        suggestions << { type: 'custom', confidence: 'low', reason: 'Could not detect a standard type. May need manual mapping.' }
      end

      suggestions
    end
  end
end

