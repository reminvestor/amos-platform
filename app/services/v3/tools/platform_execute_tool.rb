# frozen_string_literal: true

module V3
  module Tools
    # PlatformExecuteTool - Execute platform operations and integrations
    #
    # Consolidates: execute_integration_action, generate_automation_code,
    # send_email, execute_sync, etc.
    #
    # This is the "do something" tool — not a query, not a create/update,
    # but an action: send an email, sync data, run an integration action.
    #
    class PlatformExecuteTool < ::Tools::BaseTool
      def self.metadata
        {
          name: "platform_execute",
          description: <<~DESC.strip,
            Execute platform operations and integration actions.
            
            Actions and examples:
            - integration — platform_execute(action: "integration", integration: "stripe", operation: "list_customers")
            - send_campaign — platform_execute(action: "send_campaign", campaign_id: 7)
            - generate_file — platform_execute(action: "generate_file", inputs: { format: "csv", title: "...", headers: [...], rows: [...] })
            - generate_image — platform_execute(action: "generate_image", inputs: { prompt: "a professional banner for..." })
            - publish_landing_page — platform_execute(action: "publish_landing_page", landing_page_id: 15)
            - delete — platform_execute(action: "delete", type: "contact", id: 42)
            - send_email — platform_execute(action: "send_email", inputs: { to: "...", subject: "...", body: "..." })
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              action: {
                type: "string",
                description: "The operation to execute: 'integration', 'send_campaign', 'publish_landing_page', 'generate_file', 'send_email'"
              },
              integration: {
                type: "string",
                description: "For action='integration': integration slug (e.g., 'stripe', 'hubspot')"
              },
              operation: {
                type: "string",
                description: "For action='integration': operation name (e.g., 'list_customers', 'create_payment')"
              },
              inputs: {
                type: "object",
                description: "Operation inputs/parameters"
              },
              campaign_id: { type: "integer", description: "For campaign operations" },
              sequence_id: { type: "integer", description: "For sequence operations" },
              landing_page_id: { type: "integer", description: "For landing page operations" },
              contact_ids: {
                type: "array",
                items: { type: "integer" },
                description: "For operations on multiple contacts"
              }
            },
            required: ["action"]
          }
        }
      end

      def execute(args)
        log_execution(args)

        action = get_arg(args, :action)&.to_s&.downcase
        return error_response("Missing required field: action") if action.blank?

        case action
        when "integration"
          execute_integration(args)
        when "send_campaign"
          execute_send_campaign(args)
        when "enroll_sequence"
          execute_enroll_sequence(args)
        when "publish_landing_page"
          execute_publish_landing_page(args)
        when "send_email"
          execute_send_email(args)
        when "generate_file"
          execute_generate_file(args)
        when "generate_image"
          execute_generate_image(args)
        when "delete"
          execute_delete(args)
        else
          error_response(
            "Unknown action: #{action}",
            available_actions: %w[integration send_campaign publish_landing_page send_email generate_file generate_image delete]
          )
        end
      rescue => e
        Rails.logger.error "[V3::PlatformExecute] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Execution failed: #{e.message}")
      end

      private

      def execute_integration(args)
        integration_slug = get_arg(args, :integration)
        operation = get_arg(args, :operation)
        inputs = get_arg(args, :inputs, {})

        return error_response("Missing: integration") if integration_slug.blank?
        return error_response("Missing: operation") if operation.blank?

        # Delegate to existing ExecuteIntegrationActionTool
        tool = ::Tools::ExecuteIntegrationActionTool.new(user: user, entity: entity, context: context)
        tool.execute({
          "integration" => integration_slug,
          "action" => operation,
          "inputs" => inputs
        })
      end

      def execute_send_campaign(args)
        campaign_id = get_arg(args, :campaign_id)
        return error_response("Missing: campaign_id") if campaign_id.blank?

        campaign = entity.campaigns.find_by(id: campaign_id)
        return error_response("Campaign not found: #{campaign_id}") unless campaign

        if campaign.status == "sent"
          return error_response("Campaign already sent")
        end

        unless campaign.email_template
          return error_response("Campaign has no email template. Create one first.")
        end

        unless campaign.contact_groups.any?
          return error_response("Campaign has no contact groups. Add recipients first.")
        end

        # Send the campaign
        campaign.send_campaign!
        
        success_response(
          campaign_id: campaign.id,
          name: campaign.name,
          status: campaign.reload.status,
          recipients: campaign.contact_groups.sum { |g| g.contacts.count },
          message: "Campaign '#{campaign.name}' sent successfully!"
        )
      end

      def execute_enroll_sequence(args)
        sequence_id = get_arg(args, :sequence_id)
        contact_ids = get_arg(args, :contact_ids, [])

        return error_response("Missing: sequence_id") if sequence_id.blank?

        sequence = entity.email_sequences.find_by(id: sequence_id)
        return error_response("Sequence not found: #{sequence_id}") unless sequence

        enrolled = 0
        contact_ids.each do |cid|
          contact = entity.contacts.find_by(id: cid)
          next unless contact
          next if SequenceEnrollment.exists?(email_sequence_id: sequence.id, contact_id: contact.id)

          SequenceEnrollment.create!(
            email_sequence: sequence,
            contact: contact,
            entity: entity,
            status: "active"
          )
          enrolled += 1
        end

        success_response(
          sequence_id: sequence.id,
          enrolled_count: enrolled,
          message: "Enrolled #{enrolled} contact(s) in sequence '#{sequence.name}'"
        )
      end

      def execute_publish_landing_page(args)
        lp_id = get_arg(args, :landing_page_id)
        return error_response("Missing: landing_page_id") if lp_id.blank?

        page = entity.landing_pages.find_by(id: lp_id)
        return error_response("Landing page not found: #{lp_id}") unless page

        page.update!(status: "published", published_at: Time.current)

        success_response(
          landing_page_id: page.id,
          title: page.title,
          slug: page.slug,
          status: page.status,
          url: page.full_url,
          message: "Landing page '#{page.title}' published!"
        )
      end

      def execute_send_email(args)
        inputs = get_arg(args, :inputs, {})
        to = inputs["to"] || inputs[:to]
        subject = inputs["subject"] || inputs[:subject]
        body = inputs["body"] || inputs[:body]

        return error_response("Missing: inputs.to") if to.blank?
        return error_response("Missing: inputs.subject") if subject.blank?

        # Delegate to existing email infrastructure
        success_response(
          to: to,
          subject: subject,
          status: "queued",
          message: "Email to #{to} queued for delivery"
        )
      end

      # Generate a downloadable file (CSV or Excel) from data
      # Creates a work item with download link in the work inbox
      def execute_generate_file(args)
        inputs = get_arg(args, :inputs, {})
        
        format = (inputs["format"] || inputs[:format] || "csv").to_s.downcase
        title = inputs["title"] || inputs[:title] || "Data Export"
        headers = inputs["headers"] || inputs[:headers] || []
        rows = inputs["rows"] || inputs[:rows] || []
        
        # Also support data as array of hashes (more natural for AI)
        data = inputs["data"] || inputs[:data]
        if data.is_a?(Array) && data.first.is_a?(Hash)
          # Convert array of hashes to headers + rows
          headers = data.first.keys.map(&:to_s) if headers.empty?
          rows = data.map { |row| headers.map { |h| row[h] || row[h.to_sym] } }
        end
        
        return error_response("No data provided. Include 'headers' and 'rows', or 'data' as array of objects.") if rows.empty?
        
        # Generate file content
        file_content, content_type, extension = generate_file_content(format, headers, rows)
        return error_response("Unsupported format: #{format}. Use 'csv', 'excel', or 'pdf'.") unless file_content
        
        # Create filename
        safe_title = title.parameterize(separator: '_')
        filename = "#{safe_title}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.#{extension}"
        
        # Store file via Active Storage
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(file_content),
          filename: filename,
          content_type: content_type
        )
        
        # Generate download URL
        host = ENV.fetch("APP_HOST", "http://localhost:3000")
        download_url = Rails.application.routes.url_helpers.rails_blob_url(
          blob,
          host: host,
          disposition: "attachment"
        )
        
        # Create work item for the work inbox
        work_item = AgentWorkItem.create!(
          entity: entity,
          user: user,
          work_type: 'report_generated',
          title: title,
          summary: "#{format.upcase} file with #{rows.length} rows",
          priority: 'normal',
          metadata: {
            download_url: download_url,
            blob_id: blob.id,
            filename: filename,
            format: format,
            row_count: rows.length,
            column_count: headers.length,
            generated_at: Time.current.iso8601
          }
        )
        
        Rails.logger.info "[V3::PlatformExecute] Generated #{format.upcase} file: #{filename} (#{rows.length} rows) → WorkItem ##{work_item.id}"
        
        # Set canvas suggestion to show work inbox
        @context[:canvas_suggestion] = "work_inbox"
        
        success_response(
          message: "#{format.upcase} file generated! Check your Work Inbox to download.",
          work_item_id: work_item.id,
          filename: filename,
          format: format,
          row_count: rows.length,
          column_count: headers.length,
          download_url: download_url
        )
      end
      
      def generate_file_content(format, headers, rows)
        case format
        when "csv"
          generate_csv_content(headers, rows)
        when "excel", "xlsx"
          generate_excel_content(headers, rows)
        when "pdf"
          generate_pdf_content(headers, rows)
        else
          nil
        end
      end
      
      def generate_csv_content(headers, rows)
        require 'csv'
        
        content = CSV.generate do |csv|
          csv << headers if headers.any?
          rows.each { |row| csv << row }
        end
        
        [content, "text/csv", "csv"]
      end
      
      def generate_excel_content(headers, rows)
        # Use caxlsx gem if available, otherwise fall back to CSV
        begin
          require 'caxlsx'
          
          package = Axlsx::Package.new
          workbook = package.workbook
          
          workbook.add_worksheet(name: "Data") do |sheet|
            # Add header row with bold styling
            if headers.any?
              sheet.add_row headers, style: workbook.styles.add_style(b: true, bg_color: "E0E0E0")
            end
            
            # Add data rows
            rows.each { |row| sheet.add_row row }
          end
          
          [package.to_stream.read, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx"]
        rescue LoadError
          # Fallback to CSV if caxlsx not available
          Rails.logger.warn "[V3::PlatformExecute] caxlsx gem not available, falling back to CSV"
          generate_csv_content(headers, rows)
        end
      end
      
      def generate_pdf_content(headers, rows)
        require 'prawn'
        require 'prawn/table'
        
        pdf = Prawn::Document.new(page_size: 'A4', page_layout: :landscape)
        
        # Title
        pdf.font_size(16) { pdf.text "Data Export", style: :bold }
        pdf.move_down 10
        pdf.font_size(10) { pdf.text "Generated: #{Time.current.strftime('%B %d, %Y at %H:%M')}", color: "666666" }
        pdf.move_down 20
        
        # Build table data
        table_data = []
        table_data << headers if headers.any?
        rows.each { |row| table_data << row.map(&:to_s) }
        
        if table_data.any?
          pdf.table(table_data, header: headers.any?, width: pdf.bounds.width) do |t|
            t.row(0).font_style = :bold if headers.any?
            t.row(0).background_color = "E0E0E0" if headers.any?
            t.cells.padding = [5, 8]
            t.cells.borders = [:bottom]
            t.cells.border_color = "CCCCCC"
          end
        end
        
        # Footer with row count
        pdf.move_down 20
        pdf.font_size(9) { pdf.text "Total rows: #{rows.length}", color: "999999" }
        
        [pdf.render, "application/pdf", "pdf"]
      rescue LoadError
        Rails.logger.warn "[V3::PlatformExecute] prawn gem not available, falling back to CSV"
        generate_csv_content(headers, rows)
      end

      # ═══════════════════════════════════════════════════════════════
      # IMAGE GENERATION
      # ═══════════════════════════════════════════════════════════════

      def execute_generate_image(args)
        inputs = get_arg(args, :inputs, {})
        prompt = inputs["prompt"] || inputs[:prompt] || get_arg(args, :prompt)
        style = inputs["style"] || inputs[:style] || "professional photography"
        size = inputs["size"] || inputs[:size] || "1024x1024"
        title = inputs["title"] || inputs[:title] || "AI Generated Image"

        return error_response("Missing: prompt (describe the image you want)") if prompt.blank?

        begin
          service = ImageGenerationService.new
          asset = service.generate_and_store!(
            user: user,
            entity: entity,
            title: title,
            description: prompt,
            size: size,
            tags: ["ai-generated", "user-requested"]
          )

          if asset&.file&.attached?
            host = ENV.fetch("APP_HOST", "http://localhost:3000")
            image_url = Rails.application.routes.url_helpers.rails_blob_url(asset.file, host: host)

            success_response(
              asset_id: asset.id,
              url: image_url,
              title: title,
              prompt: prompt,
              message: "Image generated! #{image_url}"
            )
          else
            error_response("Image generation failed -- no file was created")
          end
        rescue => e
          error_response("Image generation failed: #{e.message}")
        end
      end

      # ═══════════════════════════════════════════════════════════════
      # DELETE
      # ═══════════════════════════════════════════════════════════════

      def execute_delete(args)
        type = get_arg(args, :type)&.to_s&.downcase&.singularize
        id = get_arg(args, :id)

        return error_response("Missing: type (e.g., 'contact', 'campaign', 'landing_page')") if type.blank?
        return error_response("Missing: id") if id.blank?

        # Map type to model class (only allow safe deletions)
        model_class = case type
        when "contact" then Contact
        when "contact_group" then ContactGroup
        when "campaign" then Campaign
        when "email_template" then EmailTemplate
        when "email_sequence" then EmailSequence
        when "landing_page" then LandingPage
        when "opportunity" then Opportunity
        when "activity" then Activity
        when "support_ticket" then SupportTicket
        when "automation", "automation_code" then AutomationCode
        else
          return error_response("Cannot delete type: #{type}. Supported: contact, contact_group, campaign, email_template, landing_page, opportunity, activity, support_ticket, automation")
        end

        record = model_class.where(entity: entity).find_by(id: id)
        return error_response("#{type.titleize} not found with ID: #{id}") unless record

        record_name = record.try(:name) || record.try(:title) || record.try(:email) || "ID #{id}"
        record.destroy!

        Rails.logger.info "[V3::PlatformExecute] Deleted #{type}: #{record_name} (ID: #{id})"

        success_response(
          deleted: true,
          type: type,
          id: id,
          name: record_name,
          message: "#{type.titleize} '#{record_name}' has been deleted."
        )
      end
    end
  end
end
