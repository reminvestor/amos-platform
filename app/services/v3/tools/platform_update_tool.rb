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
            
            For landing page section edits, include "section" and "instruction" in data:
            - platform_update(type: "landing_page", id: 189, data: { section: "hero", instruction: "Remove the image and center the text" })
            - platform_update(type: "landing_page", id: 189, data: { section: "features", instruction: "Change the headline to 'Why Choose Us'" })
            
            For full landing page HTML replacement:
            - platform_update(type: "landing_page", id: 189, data: { html_content: "<html>..." })
            
            Other examples:
            - platform_update(type: "contact", id: 42, data: { status: "active", first_name: "Jane" })
            - platform_update(type: "campaign", id: 7, data: { status: "active" })
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

        # Landing page section editing — route to specialized tool
        if type == "landing_page" && (data["section"] || data[:section])
          return edit_landing_page_section(id, data)
        end

        # Landing page section reading — route to specialized tool
        if type == "landing_page" && (data["read_sections"] || data[:read_sections])
          return read_landing_page_sections(id)
        end

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

      private

      def edit_landing_page_section(landing_page_id, data)
        section = data["section"] || data[:section]
        instruction = data["instruction"] || data[:instruction]
        action = data["action"] || data[:action] || "update"
        content = data["content"] || data[:content]

        tool = ::Tools::EditLandingPageSectionTool.new(user: user, entity: entity, context: context)
        result = tool.execute({
          "landing_page_id" => landing_page_id.to_i,
          "section" => section,
          "instruction" => instruction,
          "action" => action,
          "content" => content
        }.compact)

        # Auto-refresh the editor canvas
        if result.is_a?(Hash) && result[:success] != false
          @context[:canvas_suggestion] = "landing_page_editor"
          result[:canvas_type] = "landing_page_editor"
          result[:canvas_data] = { landing_page_id: landing_page_id.to_i }
        end

        result
      end

      def read_landing_page_sections(landing_page_id)
        tool = ::Tools::ReadLandingPageSectionsTool.new(user: user, entity: entity, context: context)
        tool.execute({ "landing_page_id" => landing_page_id.to_i })
      end
    end
  end
end
