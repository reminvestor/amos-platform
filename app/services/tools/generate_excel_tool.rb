# frozen_string_literal: true

module Tools
  class GenerateExcelTool < BaseTool
    def self.read_only?
      false
    end

    def self.metadata
      {
        name: 'generate_excel',
        description: 'Generates an Excel (.xlsx) file from provided data. Returns a download URL. Use this when user asks for data in Excel format, wants a spreadsheet with formatting, or needs multiple sheets.',
        category: 'export',
        input_schema: {
          type: 'object',
          properties: {
            title: {
              type: 'string',
              description: 'Title/name for the generated file (without extension)'
            },
            sheets: {
              type: 'array',
              description: 'Array of sheet definitions. Each sheet has a name and data array.',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string', description: 'Sheet name' },
                  data: { type: 'array', description: 'Array of row objects' },
                  headers: { type: 'array', description: 'Optional column headers' }
                }
              }
            },
            data: {
              type: 'array',
              description: 'Simple mode: Array of objects for a single sheet. Use this OR sheets, not both.',
              items: { type: 'object' }
            },
            headers: {
              type: 'array',
              description: 'Optional column headers for simple mode',
              items: { type: 'string' }
            },
            description: {
              type: 'string',
              description: 'Optional description of what this export contains'
            }
          },
          required: ['title']
        }
      }
    end

    def execute(args)
      log_execution(args)

      title = get_arg(args, :title)
      sheets = get_arg(args, :sheets)
      data = get_arg(args, :data)
      headers = get_arg(args, :headers)
      description = get_arg(args, :description)

      return error_response("Title is required") if title.blank?
      return error_response("Either 'data' or 'sheets' is required") if data.blank? && sheets.blank?

      begin
        # Normalize to sheets format
        if sheets.blank?
          sheets = [{ name: 'Data', data: data, headers: headers }]
        end

        # Generate Excel content
        excel_content = generate_excel(sheets, title)
        
        # Create filename
        filename = "#{title.parameterize}-#{Time.current.strftime('%Y%m%d-%H%M%S')}.xlsx"
        
        # Calculate total rows
        total_rows = sheets.sum { |s| s[:data]&.length || s['data']&.length || 0 }
        
        # Create the export record with attached file (goes to Work Items)
        export = create_export_record(
          filename: filename,
          content: excel_content,
          content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          title: title,
          description: description,
          format: 'xlsx',
          row_count: total_rows,
          sheet_count: sheets.length
        )

        success_response(
          export_id: export.id,
          work_item_id: export.id,
          filename: filename,
          download_url: export.download_url,
          row_count: total_rows,
          sheet_count: sheets.length,
          message: "✅ Generated Excel workbook with #{sheets.length} sheet(s) and #{total_rows} total rows. Download available in your Work Items."
        )
      rescue => e
        Rails.logger.error "Excel generation failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Failed to generate Excel: #{e.message}")
      end
    end

    private

    def generate_excel(sheets, title)
      # Use caxlsx gem for Excel generation
      package = Axlsx::Package.new
      workbook = package.workbook

      # Define styles
      header_style = workbook.styles.add_style(
        b: true,
        bg_color: '4472C4',
        fg_color: 'FFFFFF',
        alignment: { horizontal: :center },
        border: { style: :thin, color: '000000' }
      )

      date_style = workbook.styles.add_style(
        format_code: 'yyyy-mm-dd',
        border: { style: :thin, color: 'DDDDDD' }
      )

      currency_style = workbook.styles.add_style(
        format_code: '$#,##0.00',
        border: { style: :thin, color: 'DDDDDD' }
      )

      default_style = workbook.styles.add_style(
        border: { style: :thin, color: 'DDDDDD' }
      )

      sheets.each do |sheet_def|
        sheet_name = sheet_def[:name] || sheet_def['name'] || 'Sheet'
        sheet_data = sheet_def[:data] || sheet_def['data'] || []
        sheet_headers = sheet_def[:headers] || sheet_def['headers']

        next if sheet_data.empty?

        # Determine headers
        if sheet_headers.blank?
          all_keys = sheet_data.flat_map(&:keys).uniq.map(&:to_s)
          sheet_headers = all_keys
        end

        workbook.add_worksheet(name: sheet_name.to_s.truncate(31)) do |ws|
          # Add header row
          ws.add_row sheet_headers, style: header_style

          # Add data rows
          sheet_data.each do |row|
            row_values = sheet_headers.map do |header|
              value = row[header] || row[header.to_sym] || ''
              # Convert to appropriate type
              case value
              when Date, Time, DateTime
                value.to_date
              when TrueClass, FalseClass
                value ? 'Yes' : 'No'
              else
                value.to_s
              end
            end

            # Determine styles for each cell
            styles = row_values.map do |value|
              case value
              when /^\$[\d,]+\.?\d*$/, /^[\d,]+\.?\d*$/
                currency_style if value.to_s.include?('$')
              else
                default_style
              end
            end

            ws.add_row row_values, style: styles.map { |s| s || default_style }
          end

          # Auto-width columns (approximate)
          ws.column_widths(*sheet_headers.map { |h| [h.to_s.length + 5, 40].min })
        end
      end

      # Return binary content
      package.to_stream.read
    end

    def create_export_record(filename:, content:, content_type:, title:, description:, format:, row_count:, sheet_count: 1)
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
        title: "📊 #{title}",
        summary: description || "Exported #{row_count} rows across #{sheet_count} sheet(s) to Excel",
        asset_type: 'document',
        metadata: {
          format: format,
          filename: filename,
          row_count: row_count,
          sheet_count: sheet_count,
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
