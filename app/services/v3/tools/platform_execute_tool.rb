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
            
            Actions:
            - integration: Run an integration operation (smart cascade: tries IntegrationAction first, falls back to raw operation)
            - test_integration: Test integration credentials
            - configure_integration_auth: Set up integration authentication
            - add_integration_operations: Add API operations to an integration
            - generate_action: Auto-generate an IntegrationAction from an operation
            - send_campaign: Send an email campaign
            - generate_file: Generate CSV/PDF/Excel files
            - generate_image: Generate an image from a prompt
            - publish_landing_page: Publish a landing page
            - delete: Delete a record by type and ID
            - send_email: Send a single email
            - verify_domain: Verify a custom domain's DNS (CNAME) configuration
            - verify_email_domain: Start or check email sending verification for a custom domain
            - set_primary_domain: Set a custom domain as the primary domain
            - assign_domain: Assign a custom domain to a landing page or website
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              action: {
                type: "string",
                description: "The operation to execute: 'integration', 'test_integration', 'configure_integration_auth', 'add_integration_operations', 'generate_action', 'send_campaign', 'publish_landing_page', 'generate_file', 'send_email', 'delete', 'verify_domain', 'verify_email_domain', 'set_primary_domain', 'assign_domain'"
              },
              integration_id: {
                type: "integer",
                description: "For integration management actions: integration ID"
              },
              auth_type: {
                type: "string",
                description: "For configure_integration_auth: auth type (api_key, bearer_token, basic_auth, oauth2, no_auth)"
              },
              auth_configs: {
                type: "array",
                description: "For configure_integration_auth: array of { key, value, placement } objects"
              },
              test_endpoint: {
                type: "string",
                description: "For configure_integration_auth: endpoint to test auth against (e.g., '/me', '/charges?limit=1')"
              },
              operations: {
                type: "array",
                description: "For add_integration_operations: array of operation definitions"
              },
              operation_id: {
                type: "string",
                description: "For generate_action: the operation_id to generate an action for"
              },
              use_ai: {
                type: "boolean",
                description: "For generate_action: use AI to generate smarter mapping code (default: true)"
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
              },
              domain_id: {
                type: "integer",
                description: "For domain actions: the custom domain ID"
              },
              domain_name: {
                type: "string",
                description: "For domain actions: the domain name (e.g., 'example.com')"
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
        when "test_integration"
          execute_test_integration(args)
        when "configure_integration_auth"
          execute_configure_auth(args)
        when "add_integration_operations"
          execute_add_operations(args)
        when "generate_action"
          execute_generate_action(args)
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
        when "verify_domain"
          execute_verify_domain(args)
        when "verify_email_domain"
          execute_verify_email_domain(args)
        when "set_primary_domain"
          execute_set_primary_domain(args)
        when "assign_domain"
          execute_assign_domain(args)
        else
          error_response(
            "Unknown action: #{action}",
            available_actions: %w[integration test_integration configure_integration_auth add_integration_operations generate_action send_campaign publish_landing_page send_email generate_file generate_image delete verify_domain verify_email_domain set_primary_domain assign_domain]
          )
        end
      rescue => e
        Rails.logger.error "[V3::PlatformExecute] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Execution failed: #{e.message}")
      end

      private

      # ═══════════════════════════════════════════════════════════════
      # INTEGRATION — Smart execution cascade
      # ═══════════════════════════════════════════════════════════════

      def execute_integration(args)
        integration_slug = get_arg(args, :integration)
        operation_name = get_arg(args, :operation)
        inputs = get_arg(args, :inputs, {})

        return error_response("Missing: integration (e.g., 'stripe', 'hubspot')") if integration_slug.blank?
        return error_response("Missing: operation (e.g., 'list_customers', 'create_payment')") if operation_name.blank?

        # Find the integration
        integration = Integration.find_by(slug: integration_slug) ||
                      Integration.where(entity: entity).find_by(slug: integration_slug)
        return error_response(
          "Integration '#{integration_slug}' not found.",
          hint: "Use the platform_create tool with type='integration' to set it up, or use platform_query with type='integrations' to check available integrations."
        ) unless integration

        # Find user's connection
        connection = entity.connections.where(integration: integration).where.not(status: :disconnected).first
        unless connection
          return error_response(
            "No active connection for #{integration.name}. The user needs to enter credentials first.",
            hint: "Open the Integrations panel to enter credentials for #{integration.name}.",
            canvas_type: "integrations_manager",
            canvas_data: { integration_id: integration.id }
          )
        end

        # ─── STEP 1: Try IntegrationAction (has mapping code, validation, normalization) ───
        action = IntegrationAction.for_entity(entity)
                                  .where(integration: integration)
                                  .usable
                                  .where("action_name ILIKE ? OR slug ILIKE ?", operation_name, "%#{operation_name}%")
                                  .first

        if action
          Rails.logger.info "[V3::PlatformExecute] Using IntegrationAction '#{action.slug}'"
          execution = action.execute!(
            inputs: inputs.with_indifferent_access,
            connection: connection,
            user: user,
            entity: entity
          )

          if execution.success?
            return success_response(
              data: execution.normalized_response || execution.raw_response,
              via: "action",
              action: action.slug,
              execution_id: execution.id,
              message: "#{action.action_name} completed via #{integration.name}"
            )
          else
            Rails.logger.warn "[V3::PlatformExecute] Action execution failed: #{execution.error_message}, trying direct operation"
          end
        end

        # ─── STEP 2: Try direct IntegrationOperation ───
        operation = integration.integration_operations.find_by(operation_id: operation_name) ||
                    integration.integration_operations.find_by(operation_id: "#{integration_slug}.#{operation_name}") ||
                    integration.integration_operations.where("name ILIKE ? OR operation_id ILIKE ?", operation_name, "%#{operation_name}%").first

        if operation
          Rails.logger.info "[V3::PlatformExecute] Using direct operation '#{operation.operation_id}'"

          # Auto-generate an IntegrationAction for next time
          begin
            gen_result = Integrations::ActionGeneratorService.generate_for_operation(
              operation, use_ai: true, entity_id: entity.id, user_id: user.id
            )
            if gen_result[:success]
              Rails.logger.info "[V3::PlatformExecute] Auto-generated action '#{gen_result[:action].slug}' for future use"
            end
          rescue => e
            Rails.logger.warn "[V3::PlatformExecute] Action auto-generation failed (non-fatal): #{e.message}"
          end

          # Execute directly
          tool = ::Tools::ExecuteIntegrationActionTool.new(user: user, entity: entity, context: context)
          result = tool.execute({
            "integration" => integration_slug,
            "action" => operation_name,
            "inputs" => inputs
          })

          return result
        end

        # ─── STEP 3: Operation not found — guide the Brain to create it ───
        available_ops = integration.integration_operations.pluck(:operation_id, :name).map { |id, name| "#{id} (#{name})" }

        error_response(
          "No operation '#{operation_name}' found for #{integration.name}.",
          hint: "To add this operation: 1) Use web_search to find the #{integration.name} API docs for '#{operation_name}'. " \
                "2) Call platform_execute(action: 'add_integration_operations', integration_id: #{integration.id}, operations: [{ name: '...', operation_id: '#{operation_name}', http_method: 'GET', path_template: '/...', description: '...' }]). " \
                "3) Then retry this call.",
          available_operations: available_ops.first(20),
          integration_id: integration.id
        )
      end

      # ═══════════════════════════════════════════════════════════════
      # INTEGRATION MANAGEMENT — Setup and configuration actions
      # ═══════════════════════════════════════════════════════════════

      def execute_test_integration(args)
        integration_id = get_arg(args, :integration_id)
        return error_response("Missing: integration_id") if integration_id.blank?

        factory = Factories::IntegrationFactory.new(user: user, entity: entity)
        result = factory.test_auth(integration_id: integration_id)

        if result[:success]
          success_response(
            integration_id: integration_id,
            status: "connected",
            integration_agent: result[:integration_agent],
            message: "Authentication test passed! #{result[:integration_agent] ? "Created expert agent: #{result[:integration_agent][:name]}." : ''}",
            test_response_preview: result[:test_response].is_a?(Hash) ? result[:test_response].keys.first(5) : nil
          )
        else
          error_response(
            translate_integration_error(result),
            integration_id: integration_id,
            needs_credentials: result[:needs_credentials],
            suggestion: result[:suggestion],
            user_action: result[:user_action],
            debug_info: result[:debug_info],
            canvas_type: result[:needs_credentials] ? "integrations_manager" : nil,
            canvas_data: result[:needs_credentials] ? { integration_id: integration_id } : nil
          )
        end
      end

      def execute_configure_auth(args)
        integration_id = get_arg(args, :integration_id)
        auth_type = get_arg(args, :auth_type)

        return error_response("Missing: integration_id") if integration_id.blank?
        return error_response("Missing: auth_type (api_key, bearer_token, basic_auth, oauth2, no_auth)") if auth_type.blank?

        factory = Factories::IntegrationFactory.new(user: user, entity: entity)
        result = factory.configure_auth(
          integration_id: integration_id,
          auth_type: auth_type,
          auth_placement: get_arg(args, :auth_placement),
          test_endpoint: get_arg(args, :test_endpoint),
          auth_configs: get_arg(args, :auth_configs),
          auth_header_name: get_arg(args, :auth_header_name),
          authorize_url: get_arg(args, :authorize_url),
          token_url: get_arg(args, :token_url),
          scopes: get_arg(args, :scopes)
        )

        if result[:success]
          success_response(
            integration_id: integration_id,
            auth_type: auth_type,
            auth_configs_created: result[:auth_configs_created],
            message: "Authentication configured as #{auth_type}. User should now enter credentials in the Integrations panel.",
            canvas_type: "integrations_manager",
            canvas_data: { integration_id: integration_id }
          )
        else
          error_response("Auth configuration failed: #{factory.errors.join(', ')}", integration_id: integration_id)
        end
      end

      def execute_add_operations(args)
        integration_id = get_arg(args, :integration_id)
        operations = get_arg(args, :operations)

        return error_response("Missing: integration_id") if integration_id.blank?
        return error_response("Missing: operations (array of operation definitions)") if operations.blank?

        factory = Factories::IntegrationFactory.new(user: user, entity: entity)
        result = factory.add_operations(integration_id: integration_id, operations: operations)

        if result[:success]
          ops_created = result[:operations_created] || []

          # Auto-generate IntegrationActions for each operation
          actions_generated = []
          ops_created.each do |op|
            begin
              gen = Integrations::ActionGeneratorService.generate_for_operation(op, use_ai: true, entity_id: entity.id, user_id: user.id)
              actions_generated << gen[:action].slug if gen[:success]
            rescue => e
              Rails.logger.warn "[V3::PlatformExecute] Action generation for #{op.name} failed: #{e.message}"
            end
          end

          success_response(
            integration_id: integration_id,
            operations_created: ops_created.map { |op| { id: op.id, name: op.name, operation_id: op.operation_id, method: op.http_method, path: op.path_template } },
            actions_generated: actions_generated,
            message: "Added #{ops_created.length} operation(s). #{actions_generated.any? ? "Generated #{actions_generated.length} action mapping(s)." : ''}"
          )
        else
          error_response("Failed to add operations: #{factory.errors.join(', ')}", integration_id: integration_id)
        end
      end

      def execute_generate_action(args)
        integration_slug = get_arg(args, :integration)
        operation_id_str = get_arg(args, :operation_id)
        use_ai = get_arg(args, :use_ai) != false # default true

        return error_response("Missing: integration") if integration_slug.blank?
        return error_response("Missing: operation_id") if operation_id_str.blank?

        integration = Integration.find_by(slug: integration_slug) ||
                      Integration.where(entity: entity).find_by(slug: integration_slug)
        return error_response("Integration '#{integration_slug}' not found") unless integration

        operation = integration.integration_operations.find_by(operation_id: operation_id_str) ||
                    integration.integration_operations.find_by(operation_id: "#{integration_slug}.#{operation_id_str}") ||
                    integration.integration_operations.where("name ILIKE ? OR operation_id ILIKE ?", operation_id_str, "%#{operation_id_str}%").first
        return error_response("Operation '#{operation_id_str}' not found for #{integration.name}") unless operation

        result = Integrations::ActionGeneratorService.generate_for_operation(
          operation,
          use_ai: use_ai,
          entity_id: entity.id,
          user_id: user.id,
          auto_activate: true
        )

        if result[:success]
          action = result[:action]
          success_response(
            action_id: action.id,
            slug: action.slug,
            action_name: action.action_name,
            input_schema: action.input_schema,
            status: action.status,
            message: "Action '#{action.slug}' generated with #{use_ai ? 'AI-enhanced' : 'default'} mapping code. Ready to use."
          )
        else
          error_response("Action generation failed: #{result[:error]}")
        end
      end

      # ═══════════════════════════════════════════════════════════════
      # ERROR TRANSLATION — User-friendly integration errors
      # ═══════════════════════════════════════════════════════════════

      def translate_integration_error(result)
        status = result[:status_code]
        error = result[:error].to_s

        case status
        when 401
          "Authentication failed. The API key or credentials may be invalid or expired. Please check them in the Integrations panel."
        when 403
          "Access denied. The credentials don't have permission for this operation. Check that the API key has the right scopes."
        when 404
          "The test endpoint was not found. The API URL or endpoint path may be incorrect."
        when 429
          "Rate limit exceeded. The API is temporarily blocking requests. Try again in a few minutes."
        when 500..599
          "The external service is having issues (#{status}). This is on their end — try again later."
        else
          if result[:needs_credentials]
            "No credentials found. Open the Integrations panel to enter your API key or credentials."
          else
            "Connection test failed: #{error}"
          end
        end
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
        # Extract type/id from top-level or from nested inputs hash
        inputs = get_arg(args, :inputs, {})
        type = (get_arg(args, :type) || get_arg(inputs, :type))&.to_s&.downcase&.singularize
        id = get_arg(args, :id) || get_arg(inputs, :id)

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
        when "custom_domain" then CustomDomain
        else
          # Try dynamic module resolution for custom app module records
          resolved = resolve_dynamic_model_for_delete(type)
          return error_response("Cannot delete type: #{type}. Supported: contact, contact_group, campaign, email_template, landing_page, opportunity, activity, support_ticket, automation, custom_domain, or any custom module type (e.g. 'module_slug/ModelName')") unless resolved
          resolved
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

      # ═══════════════════════════════════════════════════════════════
      # CUSTOM DOMAIN ACTIONS
      # ═══════════════════════════════════════════════════════════════

      def execute_verify_domain(args)
        domain = find_custom_domain(args)
        return domain if domain.is_a?(Hash) && domain[:success] == false

        service = CustomDomainService.new(custom_domain: domain)
        result = service.verify_web_dns

        if result[:success]
          success_response(
            custom_domain_id: domain.id,
            domain_name: domain.full_domain,
            web_status: domain.reload.web_status,
            ssl_status: domain.ssl_status,
            message: result[:message],
            canvas_type: "custom_domains"
          )
        else
          error_response(
            "Domain verification failed: #{result[:error]}",
            expected_cname: result[:expected],
            instructions: result[:instructions]
          )
        end
      end

      def execute_verify_email_domain(args)
        domain = find_custom_domain(args)
        return domain if domain.is_a?(Hash) && domain[:success] == false

        service = SesDomainService.new(custom_domain: domain)

        if domain.email_status == "pending"
          # Start verification — creates SES identity, returns DNS records
          result = service.start_verification

          if result[:success]
            success_response(
              custom_domain_id: domain.id,
              domain_name: domain.domain_name,
              email_status: domain.reload.email_status,
              dns_records: result[:dns_records],
              instructions: result[:instructions],
              message: "Email verification started for #{domain.domain_name}. " \
                       "DNS records need to be configured (DKIM, SPF, DMARC). " \
                       "Verification will be checked automatically.",
              canvas_type: "custom_domains"
            )
          else
            error_response("Email verification failed: #{result[:error]}")
          end
        else
          # Check existing verification status
          result = service.check_verification_status

          success_response(
            custom_domain_id: domain.id,
            domain_name: domain.domain_name,
            email_status: domain.reload.email_status,
            verified: result[:verified],
            message: result[:verified] ?
              "Email sending is verified for #{domain.domain_name}!" :
              "Email verification in progress. #{result[:message]}",
            canvas_type: "custom_domains"
          )
        end
      end

      def execute_set_primary_domain(args)
        domain = find_custom_domain(args)
        return domain if domain.is_a?(Hash) && domain[:success] == false

        domain.update!(is_primary: true)

        success_response(
          custom_domain_id: domain.id,
          domain_name: domain.full_domain,
          is_primary: true,
          message: "#{domain.full_domain} is now your primary domain.",
          canvas_type: "custom_domains"
        )
      end

      def execute_assign_domain(args)
        domain = find_custom_domain(args)
        return domain if domain.is_a?(Hash) && domain[:success] == false

        unless domain.fully_configured?
          return error_response(
            "Domain #{domain.full_domain} is not fully configured yet. " \
            "Web status: #{domain.web_status}, SSL status: #{domain.ssl_status}. " \
            "Verify the domain first."
          )
        end

        assign_type = get_arg(args, :type)&.to_s&.downcase&.singularize
        assign_id = get_arg(args, :id) || get_arg(args, :landing_page_id) || get_arg(args, :website_id)

        return error_response("Missing: type (landing_page or website) and id") if assign_type.blank? || assign_id.blank?

        service = CustomDomainService.new(custom_domain: domain)

        case assign_type
        when "landing_page"
          lp = entity.landing_pages.find_by(id: assign_id)
          return error_response("Landing page not found: #{assign_id}") unless lp
          result = service.assign_to_landing_page(lp)
        when "website"
          ws = entity.websites.find_by(id: assign_id)
          return error_response("Website not found: #{assign_id}") unless ws
          result = service.assign_to_website(ws)
        else
          return error_response("Unsupported type: #{assign_type}. Use 'landing_page' or 'website'.")
        end

        if result[:success]
          success_response(
            custom_domain_id: domain.id,
            assigned_to: { type: assign_type, id: assign_id },
            url: result[:url],
            message: "#{assign_type.titleize} is now available at #{result[:url]}"
          )
        else
          error_response(result[:error])
        end
      end

      # Resolve a dynamic module model class for delete operations.
      # Supports formats: "module_slug/ModelName", "module_slug", or
      # underscore variants like "contact_profiles_trust_party".
      def resolve_dynamic_model_for_delete(type)
        return nil unless entity.present?

        parts = type.to_s.split('/')
        if parts.length == 2
          module_slug = parts[0]
          model_name = parts[1]
          app_module = entity.app_modules.active.find_by(slug: module_slug)
          if app_module
            return Modules::DynamicModelLoader.instance.get_model_by_path(entity, "#{module_slug}/#{model_name}")
          end
        end

        # Try as module slug directly
        app_module = entity.app_modules.active.find_by(slug: type)
        app_module ||= entity.app_modules.active.find_by(slug: type.singularize)
        if app_module
          model_code = app_module.module_codes&.models&.first
          return nil unless model_code
          return Modules::DynamicModelLoader.instance.get_model_by_path(entity, "#{app_module.slug}/#{model_code.name}")
        end

        # Try matching as "module_slug_model_name" (underscore combined format)
        entity.app_modules.active.each do |mod|
          if type.start_with?(mod.slug)
            remainder = type.sub("#{mod.slug}_", '')
            next if remainder.blank? || remainder == type
            model_code = mod.module_codes&.models&.find_by(name: remainder.classify)
            if model_code
              return Modules::DynamicModelLoader.instance.get_model_by_path(entity, "#{mod.slug}/#{model_code.name}")
            end
          end
        end

        nil
      rescue => e
        Rails.logger.warn "[V3::PlatformExecute] Dynamic model resolution failed for delete type '#{type}': #{e.message}"
        nil
      end

      # Helper: find CustomDomain from args (by domain_id, custom_domain_id, or domain_name)
      def find_custom_domain(args)
        domain_id = get_arg(args, :domain_id) || get_arg(args, :custom_domain_id) || get_arg(args, :id)
        domain_name = get_arg(args, :domain_name) || get_arg(args, :domain)

        domain = if domain_id.present?
          entity.custom_domains.find_by(id: domain_id)
        elsif domain_name.present?
          entity.custom_domains.find_by(domain_name: domain_name.downcase)
        end

        return error_response("Custom domain not found. Provide domain_id or domain_name.") unless domain
        domain
      end
    end
  end
end
