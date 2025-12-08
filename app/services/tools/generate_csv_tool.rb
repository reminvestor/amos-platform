# frozen_string_literal: true

module Tools
  class GenerateCsvTool < BaseTool
    def self.read_only?
      false
    end

    def self.metadata
      {
        name: 'generate_csv',
        description: 'Generates a CSV file from provided data. Returns a download URL. Use this when user asks for data in CSV format or wants to export/download data as a spreadsheet.',
        category: 'export',
        input_schema: {
          type: 'object',
          properties: {
            title: {
              type: 'string',
              description: 'Title/name for the generated file (without extension)'
            },
            data: {
              type: 'array',
              description: 'Array of objects to convert to CSV. Each object becomes a row, keys become headers.',
              items: { type: 'object' }
            },
            headers: {
              type: 'array',
              description: 'Optional: Specific column headers to include (in order). If not provided, uses all keys from first row.',
              items: { type: 'string' }
            },
            description: {
              type: 'string',
              description: 'Optional description of what this export contains'
            }
          },
          required: ['title', 'data']
        }
      }
    end

    def execute(args)
      log_execution(args)

      title = get_arg(args, :title)
      data = get_arg(args, :data)
      headers = get_arg(args, :headers)
      description = get_arg(args, :description)

      return error_response("Title is required") if title.blank?
      return error_response("Data is required") if data.blank?
      return error_response("Data must be an array") unless data.is_a?(Array)
      return error_response("Data array is empty") if data.empty?

      begin
        # Generate CSV content
        csv_content = generate_csv(data, headers)
        
        # Create a temporary file and attach it
        filename = "#{title.parameterize}-#{Time.current.strftime('%Y%m%d-%H%M%S')}.csv"
        
        # Create the export record with attached file (goes to Work Items)
        export = create_export_record(
          filename: filename,
          content: csv_content,
          content_type: 'text/csv',
          title: title,
          description: description,
          format: 'csv',
          row_count: data.length
        )

        success_response(
          export_id: export.id,
          work_item_id: export.id,
          filename: filename,
          download_url: export.download_url,
          row_count: data.length,
          column_count: headers&.length || data.first&.keys&.length || 0,
          message: "✅ Generated CSV with #{data.length} rows. Download available in your Work Items."
        )
      rescue => e
        Rails.logger.error "CSV generation failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Failed to generate CSV: #{e.message}")
      end
    end

    private

    def generate_csv(data, headers = nil)
      require 'csv'

      # Determine headers
      if headers.blank?
        # Collect all unique keys from all rows
        all_keys = data.flat_map(&:keys).uniq.map(&:to_s)
        headers = all_keys
      end

      CSV.generate do |csv|
        # Header row
        csv << headers

        # Data rows
        data.each do |row|
          csv << headers.map { |header| row[header] || row[header.to_sym] || '' }
        end
      end
    end

    def create_export_record(filename:, content:, content_type:, title:, description:, format:, row_count:)
      # Store file directly to Active Storage
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(content),
        filename: filename,
        content_type: content_type
      )

      download_url = Rails.application.routes.url_helpers.rails_blob_path(
        blob,
        only_path: true,
        disposition: 'attachment'
      )

      # Create AgentWorkItem to track this export (this is the agent inbox)
      work_item = AgentWorkItem.create!(
        user: @user,
        entity: @entity,
        work_type: 'report_generated',
        title: "📄 #{title}",
        summary: description || "Exported #{row_count} rows to #{format.upcase}",
        asset_type: 'document',
        metadata: {
          format: format,
          filename: filename,
          row_count: row_count,
          generated_at: Time.current.iso8601,
          blob_id: blob.id,
          download_url: download_url
        }
      )

      # Return work item info
      OpenStruct.new(
        id: work_item.id,
        download_url: download_url
      )
    end
  end
end
