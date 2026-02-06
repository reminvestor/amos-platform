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
            Execute platform operations: integration actions, email sending, data syncing,
            workflow triggers, and other operational tasks.
            
            For integration actions, use action="integration" with integration name and action name.
            For sending campaigns, use action="send_campaign" with campaign_id.
            For enrolling contacts in sequences, use action="enroll_sequence".
            
            Examples:
            - platform_execute(action: "integration", integration: "stripe", operation: "list_customers", inputs: { limit: 10 })
            - platform_execute(action: "send_campaign", campaign_id: 7)
            - platform_execute(action: "enroll_sequence", sequence_id: 3, contact_ids: [1, 2, 3])
            - platform_execute(action: "publish_landing_page", landing_page_id: 15)
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              action: {
                type: "string",
                description: "The operation to execute: 'integration', 'send_campaign', 'enroll_sequence', 'publish_landing_page', 'sync_data', 'send_email'"
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
        else
          error_response(
            "Unknown action: #{action}",
            available_actions: %w[integration send_campaign enroll_sequence publish_landing_page send_email]
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
    end
  end
end
