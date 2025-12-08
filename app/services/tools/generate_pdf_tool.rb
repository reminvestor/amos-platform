# frozen_string_literal: true

module Tools
  class GeneratePdfTool < BaseTool
    def self.read_only?
      false
    end

    def self.metadata
      {
        name: 'generate_pdf',
        description: 'Generates a PDF document from provided content. Returns a download URL. Use this when user asks for a PDF, report, or printable document.',
        category: 'export',
        input_schema: {
          type: 'object',
          properties: {
            title: {
              type: 'string',
              description: 'Title of the PDF document'
            },
            content: {
              type: 'string',
              description: 'Main content/body text for the PDF. Supports basic markdown-like formatting.'
            },
            sections: {
              type: 'array',
              description: 'Optional: Structured sections with headers and content',
              items: {
                type: 'object',
                properties: {
                  heading: { type: 'string', description: 'Section heading' },
                  content: { type: 'string', description: 'Section content' },
                  table: { 
                    type: 'object',
                    description: 'Optional table data',
                    properties: {
                      headers: { type: 'array', items: { type: 'string' } },
                      rows: { type: 'array', items: { type: 'array' } }
                    }
                  }
                }
              }
            },
            data: {
              type: 'array',
              description: 'Optional: Data array to include as a table in the PDF',
              items: { type: 'object' }
            },
            subtitle: {
              type: 'string',
              description: 'Optional subtitle for the document'
            },
            footer: {
              type: 'string',
              description: 'Optional footer text'
            },
            description: {
              type: 'string',
              description: 'Optional description for the work item'
            }
          },
          required: ['title']
        }
      }
    end

    def execute(args)
      log_execution(args)

      title = get_arg(args, :title)
      content = get_arg(args, :content)
      sections = get_arg(args, :sections)
      data = get_arg(args, :data)
      subtitle = get_arg(args, :subtitle)
      footer = get_arg(args, :footer)
      description = get_arg(args, :description)

      return error_response("Title is required") if title.blank?
      return error_response("Either content, sections, or data is required") if content.blank? && sections.blank? && data.blank?

      begin
        # Generate PDF content
        pdf_content = generate_pdf(
          title: title,
          subtitle: subtitle,
          content: content,
          sections: sections,
          data: data,
          footer: footer
        )
        
        # Create filename
        filename = "#{title.parameterize}-#{Time.current.strftime('%Y%m%d-%H%M%S')}.pdf"
        
        # Create the export record with attached file (goes to Work Items)
        export = create_export_record(
          filename: filename,
          content: pdf_content,
          content_type: 'application/pdf',
          title: title,
          description: description,
          format: 'pdf'
        )

        success_response(
          export_id: export.id,
          work_item_id: export.id,
          filename: filename,
          download_url: export.download_url,
          page_count: 1, # Prawn doesn't easily give page count without rendering
          message: "✅ Generated PDF document '#{title}'. Download available in your Work Items."
        )
      rescue => e
        Rails.logger.error "PDF generation failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Failed to generate PDF: #{e.message}")
      end
    end

    private

    def generate_pdf(title:, subtitle: nil, content: nil, sections: nil, data: nil, footer: nil)
      Prawn::Document.new(page_size: 'LETTER', margin: [50, 50, 50, 50]) do |pdf|
        # Define colors
        primary_color = '4472C4'
        text_color = '333333'
        muted_color = '666666'

        # Title
        pdf.fill_color primary_color
        pdf.text title, size: 24, style: :bold
        pdf.fill_color text_color

        # Subtitle
        if subtitle.present?
          pdf.move_down 5
          pdf.fill_color muted_color
          pdf.text subtitle, size: 12, style: :italic
          pdf.fill_color text_color
        end

        # Date
        pdf.move_down 5
        pdf.fill_color muted_color
        pdf.text "Generated: #{Time.current.strftime('%B %d, %Y at %I:%M %p')}", size: 9
        pdf.fill_color text_color

        # Divider line
        pdf.move_down 15
        pdf.stroke_color primary_color
        pdf.line_width = 2
        pdf.stroke_horizontal_rule
        pdf.move_down 20

        # Main content
        if content.present?
          render_content(pdf, content)
          pdf.move_down 15
        end

        # Sections
        if sections.present?
          sections.each do |section|
            section = section.with_indifferent_access
            
            # Section heading
            if section[:heading].present?
              pdf.fill_color primary_color
              pdf.text section[:heading], size: 14, style: :bold
              pdf.fill_color text_color
              pdf.move_down 8
            end

            # Section content
            if section[:content].present?
              render_content(pdf, section[:content])
              pdf.move_down 10
            end

            # Section table
            if section[:table].present?
              render_table(pdf, section[:table][:headers], section[:table][:rows])
              pdf.move_down 15
            end
          end
        end

        # Data table
        if data.present? && data.is_a?(Array) && data.any?
          headers = data.first.keys.map(&:to_s)
          rows = data.map { |row| headers.map { |h| row[h] || row[h.to_sym] || '' } }
          render_table(pdf, headers, rows)
        end

        # Footer
        if footer.present?
          pdf.move_down 30
          pdf.fill_color muted_color
          pdf.text footer, size: 9, align: :center
          pdf.fill_color text_color
        end

        # Page numbers
        pdf.number_pages '<page> of <total>',
          at: [pdf.bounds.right - 100, 0],
          width: 100,
          align: :right,
          size: 9,
          color: muted_color

      end.render
    end

    def render_content(pdf, content)
      # Simple markdown-like parsing
      lines = content.to_s.split("\n")
      
      lines.each do |line|
        case line
        when /^### (.+)/
          pdf.move_down 5
          pdf.text $1, size: 12, style: :bold
          pdf.move_down 3
        when /^## (.+)/
          pdf.move_down 8
          pdf.text $1, size: 14, style: :bold
          pdf.move_down 5
        when /^# (.+)/
          pdf.move_down 10
          pdf.text $1, size: 16, style: :bold
          pdf.move_down 8
        when /^[-*] (.+)/
          pdf.text "• #{$1}", size: 10, indent_paragraphs: 15
        when /^\d+\. (.+)/
          pdf.text line, size: 10, indent_paragraphs: 15
        when /^\*\*(.+)\*\*/
          pdf.text $1, size: 10, style: :bold
        when ''
          pdf.move_down 5
        else
          pdf.text line, size: 10, leading: 3
        end
      end
    end

    def render_table(pdf, headers, rows)
      return if headers.blank? || rows.blank?

      table_data = [headers] + rows.map { |row| row.map(&:to_s) }
      
      pdf.table(table_data, width: pdf.bounds.width) do |table|
        table.row(0).background_color = '4472C4'
        table.row(0).text_color = 'FFFFFF'
        table.row(0).font_style = :bold
        table.row(0).size = 10
        table.cells.padding = [8, 10]
        table.cells.border_width = 0.5
        table.cells.border_color = 'DDDDDD'
        table.cells.size = 9
        
        # Alternate row colors
        rows.length.times do |i|
          table.row(i + 1).background_color = i.even? ? 'FFFFFF' : 'F5F5F5'
        end
      end
    end

    def create_export_record(filename:, content:, content_type:, title:, description:, format:)
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
        title: "📑 #{title}",
        summary: description || "Generated PDF document",
        asset_type: 'document',
        metadata: {
          format: format,
          filename: filename,
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
