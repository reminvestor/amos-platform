# frozen_string_literal: true

module V3
  module Tools
    # PlatformUpdateTool - Universal update tool for all platform objects
    #
    # Consolidates: update_object, update_*, edit_*
    #
    class PlatformUpdateTool < ::Tools::BaseTool
      def self.metadata
        {
          name: "platform_update",
          description: <<~DESC.strip,
            Update any existing platform object by type and ID.
            
            Supports: contacts, campaigns, landing pages, email templates, email sequences,
            contact groups, opportunities, activities, and custom module records.
            
            Only the fields you specify will be updated.
            
            Examples:
            - platform_update(type: "contact", id: 42, data: { status: "active", first_name: "Jane" })
            - platform_update(type: "campaign", id: 7, data: { status: "active", add_contact_group_ids: [1, 2] })
            - platform_update(type: "landing_page", id: 15, data: { status: "published" })
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              type: {
                type: "string",
                description: "Object type to update (contact, campaign, landing_page, email_template, etc.)"
              },
              id: {
                type: ["string", "integer"],
                description: "ID of the object to update"
              },
              data: {
                type: "object",
                description: "Fields to update. Only specified fields will change."
              }
            },
            required: %w[type id data]
          }
        }
      end

      def execute(args)
        log_execution(args)

        type = get_arg(args, :type)&.to_s&.downcase&.singularize&.underscore
        id = get_arg(args, :id)
        data = get_arg(args, :data, {})

        return error_response("Missing required field: type") if type.blank?
        return error_response("Missing required field: id") if id.blank?
        return error_response("Missing required field: data") if data.blank?

        # Delegate to existing UpdateObjectTool
        update_tool = ::Tools::UpdateObjectTool.new(user: user, entity: entity, context: context)
        
        update_tool.execute({
          "object_type" => type,
          "id" => id,
          "data" => data
        })
      rescue => e
        Rails.logger.error "[V3::PlatformUpdate] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Update failed: #{e.message}")
      end
    end
  end
end
