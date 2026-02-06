# frozen_string_literal: true

module V3
  module Tools
    # PlatformCreateTool - Universal create tool for all platform objects
    #
    # Consolidates: create_object, create_*, generate_*
    #
    # The model says what to create, we handle routing and validation.
    #
    class PlatformCreateTool < ::Tools::BaseTool
      def self.metadata
        {
          name: "platform_create",
          description: <<~DESC.strip,
            Create any platform object: contacts, campaigns, email templates, sequences,
            landing pages, contact groups, opportunities, activities, bounties, support tickets, etc.
            
            For landing pages, use type="landing_page" with a description and the system
            will handle the full Plan → Build workflow.
            
            Examples:
            - platform_create(type: "contact", data: { email: "j@example.com", first_name: "Jane" })
            - platform_create(type: "campaign", data: { name: "Summer Sale", email_template_id: 5 })
            - platform_create(type: "email_template", data: { name: "Welcome", subject: "Welcome!", body: "<h1>Hi!</h1>" })
            - platform_create(type: "contact_group", data: { name: "VIP Customers" })
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              type: {
                type: "string",
                description: "Object type to create (contact, campaign, email_template, contact_group, email_sequence, opportunity, activity, landing_page, support_ticket, bounty)"
              },
              data: {
                type: "object",
                description: "Object data. Fields depend on type. Use platform_query(type='schema', object='typename') to see available fields."
              }
            },
            required: %w[type data]
          }
        }
      end

      def execute(args)
        log_execution(args)

        type = get_arg(args, :type)&.to_s&.downcase&.singularize&.underscore
        data = get_arg(args, :data, {})

        return error_response("Missing required field: type") if type.blank?
        return error_response("Missing required field: data") if data.blank?

        # Delegate to the existing CreateObjectTool which already has all the logic
        # This is a thin wrapper that normalizes the interface
        create_tool = ::Tools::CreateObjectTool.new(user: user, entity: entity, context: context)
        
        # Normalize type to plural (what CreateObjectTool expects)
        plural_type = type.pluralize
        
        create_tool.execute({
          "object_type" => plural_type,
          "data" => data
        })
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Creation failed: #{e.message}")
      end
    end
  end
end
