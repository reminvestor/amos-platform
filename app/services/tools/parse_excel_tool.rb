# frozen_string_literal: true

module Tools
  class ParseExcelTool < BaseTool
    def self.metadata
      {
        name: "parse_excel",
        description: "Parse an Excel file (.xlsx, .xls) or spreadsheet. Returns structured data with accurate values. Use this for any spreadsheet analysis, data extraction, or when user uploads an Excel file.",
        category: "data",
        input_schema: {
          type: "object",
          properties: {
            source: {
              type: "string",
              description: "Source: 'upload' for recently uploaded file, 'url' for remote file, or 'asset_id' for specific document"
            },
            file_identifier: {
              type: "string",
              description: "Filename, URL, or asset ID to parse"
            },
            sheet_name: {
              type: "string",
              description: "Specific sheet name to parse (default: first sheet)"
            },
            sheet_index: {
              type: "integer",
              description: "Sheet index (0-based) if sheet_name not provided"
            },
            has_headers: {
              type: "boolean",
              description: "Whether first row contains headers (default: true)"
            },
            preview_only: {
              type: "boolean",
              description: "Only return first 10 rows as preview (default: false)"
            },
            start_row: {
              type: "integer",
              description: "Row to start parsing from (1-based, default: 1)"
            }
          },
          required: ["source", "file_identifier"]
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)

      source = get_arg(args, :source)
      file_identifier = get_arg(args, :file_identifier)
      sheet_name = get_arg(args, :sheet_name)
      sheet_index = get_arg(args, :sheet_index, 0)
      has_headers = get_arg(args, :has_headers, true)
      preview_only = get_arg(args, :preview_only, false)
      start_row = get_arg(args, :start_row, 1)

      if error = validate_required_args(args, [:source, :file_identifier])
        return error
      end

      begin
        require 'roo'
      rescue LoadError
        return error_response("Excel parsing library not available. Please install the 'roo' gem.")
      end

      # Get the file
      file_result = fetch_file(source, file_identifier)
      return file_result if file_result[:success] == false

      file_path = file_result[:path]
      original_filename = file_result[:filename]

      begin
        # Open the spreadsheet
        spreadsheet = open_spreadsheet(file_path, original_filename)
        return spreadsheet if spreadsheet.is_a?(Hash) && spreadsheet[:success] == false

        # Get available sheets
        available_sheets = spreadsheet.sheets

        # Select the sheet
        if sheet_name.present?
          unless available_sheets.include?(sheet_name)
            return error_response("Sheet '#{sheet_name}' not found. Available sheets: #{available_sheets.join(', ')}")
          end
          spreadsheet.default_sheet = sheet_name
        else
          spreadsheet.default_sheet = available_sheets[sheet_index] || available_sheets.first
        end

        current_sheet = spreadsheet.default_sheet

        # Parse the data
        first_row = [start_row, spreadsheet.first_row].compact.max
        last_row = spreadsheet.last_row
        first_col = spreadsheet.first_column
        last_col = spreadsheet.last_column

        return error_response("Spreadsheet is empty") if last_row.nil? || last_col.nil?

        # Extract headers
        if has_headers
          headers = (first_col..last_col).map do |col|
            value = spreadsheet.cell(first_row, col)
            normalize_header(value, col)
          end
          data_start_row = first_row + 1
        else
          headers = (first_col..last_col).map { |col| "column_#{col}" }
          data_start_row = first_row
        end

        # Extract data rows
        records = []
        row_limit = preview_only ? [data_start_row + 9, last_row].min : last_row

        (data_start_row..row_limit).each do |row_num|
          row_data = {}
          headers.each_with_index do |header, idx|
            col = first_col + idx
            cell_value = spreadsheet.cell(row_num, col)
            # Preserve numeric types
            row_data[header] = format_cell_value(cell_value)
          end
          records << row_data
        end

        total_rows = last_row - data_start_row + 1
        truncated = preview_only && total_rows > 10

        # Analyze field types
        field_analysis = analyze_fields(headers, records)

        # Calculate summary statistics for numeric columns
        numeric_summary = calculate_numeric_summary(headers, records, field_analysis)

        success_response(
          parsed: true,
          source: source,
          filename: original_filename,
          sheet: current_sheet,
          available_sheets: available_sheets,
          total_rows: total_rows,
          columns: headers,
          column_count: headers.length,
          field_analysis: field_analysis,
          numeric_summary: numeric_summary,
          records: records,
          truncated: truncated,
          message: "Successfully parsed #{total_rows} rows from '#{current_sheet}' with #{headers.length} columns.#{truncated ? ' Showing first 10 rows.' : ''}"
        )

      rescue => e
        Rails.logger.error "Excel parsing failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Failed to parse Excel file: #{e.message}")
      ensure
        # Clean up temp file if created
        File.delete(file_path) if file_path && File.exist?(file_path) && file_result[:temp_file]
      end
    end

    private

    def fetch_file(source, identifier)
      case source
      when 'upload'
        fetch_uploaded_file(identifier)
      when 'url'
        fetch_from_url(identifier)
      when 'asset_id'
        fetch_by_asset_id(identifier)
      else
        error_response("Invalid source: #{source}. Use 'upload', 'url', or 'asset_id'.")
      end
    end

    def fetch_uploaded_file(identifier)
      # Check RAG documents - SORT BY MOST RECENT FIRST to avoid returning old documents
      all_docs = entity&.rag_stores&.flat_map(&:rag_documents)&.sort_by { |d| -(d.created_at&.to_i || 0) } || []
      
      # Prefer exact filename match, then fall back to partial match
      doc = all_docs.find { |d| d.original_filename&.downcase == identifier.downcase } ||
            all_docs.find do |d|
              d.original_filename&.downcase&.include?(identifier.downcase) ||
              d.title&.downcase&.include?(identifier.downcase)
            end

      if doc&.file&.attached?
        temp_file = Tempfile.new(['excel', File.extname(doc.original_filename)])
        temp_file.binmode
        temp_file.write(doc.file.download)
        temp_file.rewind
        return { success: true, path: temp_file.path, filename: doc.original_filename, temp_file: true }
      end

      # Check ActiveStorage blobs
      if defined?(ActiveStorage::Blob)
        blob = ActiveStorage::Blob.find_by("filename ILIKE ?", "%#{identifier}%")
        if blob
          temp_file = Tempfile.new(['excel', File.extname(blob.filename.to_s)])
          temp_file.binmode
          temp_file.write(blob.download)
          temp_file.rewind
          return { success: true, path: temp_file.path, filename: blob.filename.to_s, temp_file: true }
        end
      end

      # Check ImageAsset (recent uploads) - filename is in ActiveStorage blob
      assets = ImageAsset.where(entity: entity)
                         .joins(file_attachment: :blob)
                         .where("active_storage_blobs.filename ILIKE ?", "%#{identifier}%")
                         .order(created_at: :desc)
      asset = assets.first
      
      if asset&.file&.attached?
        filename = asset.file.filename.to_s
        temp_file = Tempfile.new(['excel', File.extname(filename)])
        temp_file.binmode
        temp_file.write(asset.file.download)
        temp_file.rewind
        return { success: true, path: temp_file.path, filename: filename, temp_file: true }
      end

      error_response("Could not find uploaded file: #{identifier}")
    end

    def fetch_from_url(url)
      require 'net/http'
      require 'uri'

      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        ext = File.extname(uri.path).presence || '.xlsx'
        temp_file = Tempfile.new(['excel', ext])
        temp_file.binmode
        temp_file.write(response.body)
        temp_file.rewind
        { success: true, path: temp_file.path, filename: File.basename(uri.path), temp_file: true }
      else
        error_response("Failed to download file: HTTP #{response.code}")
      end
    rescue => e
      error_response("Failed to fetch URL: #{e.message}")
    end

    def fetch_by_asset_id(asset_id)
      asset = ImageAsset.find_by(id: asset_id, entity: entity)
      return error_response("Asset not found: #{asset_id}") unless asset&.file&.attached?

      temp_file = Tempfile.new(['excel', File.extname(asset.original_filename)])
      temp_file.binmode
      temp_file.write(asset.file.download)
      temp_file.rewind
      { success: true, path: temp_file.path, filename: asset.original_filename, temp_file: true }
    end

    def open_spreadsheet(path, filename)
      extension = File.extname(filename).downcase

      case extension
      when '.xlsx'
        Roo::Excelx.new(path)
      when '.xls'
        Roo::Excel.new(path)
      when '.ods'
        Roo::OpenOffice.new(path)
      when '.csv'
        Roo::CSV.new(path)
      else
        # Try to detect format
        begin
          Roo::Spreadsheet.open(path)
        rescue => e
          error_response("Unsupported file format: #{extension}. Supported: .xlsx, .xls, .ods, .csv")
        end
      end
    end

    def normalize_header(value, col)
      return "column_#{col}" if value.blank?
      value.to_s.strip.downcase.gsub(/\s+/, '_').gsub(/[^a-z0-9_]/, '')
    end

    def format_cell_value(value)
      return nil if value.nil?
      
      case value
      when Float
        # Check if it's a whole number
        value == value.to_i ? value.to_i : value.round(6)
      when DateTime, Time
        value.iso8601
      when Date
        value.to_s
      else
        value.to_s.strip
      end
    end

    def analyze_fields(headers, records)
      return {} if records.empty?

      headers.to_h do |header|
        values = records.map { |r| r[header] }.compact
        
        types = values.map do |v|
          case v
          when Integer then :integer
          when Float then :decimal
          when TrueClass, FalseClass then :boolean
          else
            if v.to_s.match?(/^\d{4}-\d{2}-\d{2}/)
              :date
            elsif v.to_s.match?(/^[\d.,]+$/) && v.to_s.gsub(/[,.]/, '').match?(/^\d+$/)
              :numeric_string
            else
              :string
            end
          end
        end

        primary_type = types.group_by(&:itself).max_by { |_, v| v.count }&.first || :unknown
        
        [header, {
          type: primary_type,
          sample_values: values.first(3),
          non_null_count: values.count,
          null_count: records.count - values.count
        }]
      end
    end

    def calculate_numeric_summary(headers, records, field_analysis)
      return {} if records.empty?

      summary = {}

      field_analysis.each do |header, info|
        next unless [:integer, :decimal, :numeric_string].include?(info[:type])

        values = records.map { |r| r[header] }.compact.map do |v|
          v.is_a?(Numeric) ? v : v.to_s.gsub(/[,$]/, '').to_f
        end.select { |v| v.finite? rescue false }

        next if values.empty?

        summary[header] = {
          sum: values.sum.round(2),
          average: (values.sum / values.count.to_f).round(2),
          min: values.min,
          max: values.max,
          count: values.count
        }
      end

      summary
    end
  end
end
