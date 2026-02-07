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
            Update any existing platform object by type and ID. Only specified fields change.
            
            Also supports schema extensions:
            - Add custom field: platform_update(type: "schema", id: "contact", data: { add_field: { name: "industry", field_type: "string" } })
            - Remove custom field: platform_update(type: "schema", id: "contact", data: { remove_field: "industry" })
            
            Other examples:
            - platform_update(type: "contact", id: 42, data: { lifecycle_stage: "customer" })
            - platform_update(type: "landing_page", id: 189, data: { section: "hero", instruction: "Center the text" })
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

        # Schema extension — add/remove custom fields
        if type == "schema"
          return manage_custom_fields(id, data)
        end

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

      # ═══════════════════════════════════════════════════════════════
      # CUSTOM FIELD MANAGEMENT
      # ═══════════════════════════════════════════════════════════════

      def manage_custom_fields(model_type, data)
        model_type = model_type.to_s.classify  # "contact" → "Contact"

        unless CustomFieldDefinition::SUPPORTED_MODELS.include?(model_type)
          return error_response(
            "Cannot add custom fields to #{model_type}. Supported: #{CustomFieldDefinition::SUPPORTED_MODELS.join(', ')}"
          )
        end

        if data["add_field"] || data[:add_field]
          add_custom_field(model_type, data["add_field"] || data[:add_field])
        elsif data["remove_field"] || data[:remove_field]
          remove_custom_field(model_type, data["remove_field"] || data[:remove_field])
        elsif data["list_fields"] || data[:list_fields]
          list_custom_fields(model_type)
        else
          error_response("Specify add_field, remove_field, or list_fields")
        end
      end

      def add_custom_field(model_type, field_data)
        field_data = field_data.with_indifferent_access if field_data.is_a?(Hash)

        name = field_data[:name] || field_data[:field_name]
        return error_response("Missing: name for custom field") if name.blank?

        field_type = field_data[:field_type] || field_data[:type] || "string"
        label = field_data[:label] || name.titleize
        description = field_data[:description]
        required = field_data[:required] || false
        options = field_data[:options] || []
        default_value = field_data[:default]

        # Check for duplicate
        existing = CustomFieldDefinition.find_by(entity: entity, model_type: model_type, field_name: name.downcase.gsub(/\s+/, '_'))
        if existing
          return error_response("Custom field '#{name}' already exists on #{model_type}")
        end

        field_def = CustomFieldDefinition.create!(
          entity: entity,
          model_type: model_type,
          field_name: name.downcase.gsub(/\s+/, '_'),
          field_type: field_type,
          field_label: label,
          field_description: description,
          default_value: default_value&.to_s,
          options: options.is_a?(Array) ? options.map { |o| { "value" => o.to_s, "label" => o.to_s } } : [],
          validations: required ? { "required" => true } : {},
          active: true
        )

        Rails.logger.info "[V3::PlatformUpdate] Added custom field '#{name}' (#{field_type}) to #{model_type}"

        success_response(
          field_id: field_def.id,
          model: model_type,
          field_name: field_def.field_name,
          field_type: field_def.field_type,
          label: field_def.label,
          message: "Custom field '#{field_def.label}' added to #{model_type}. You can now set it via custom_fields: { #{field_def.field_name}: value }"
        )
      end

      def remove_custom_field(model_type, field_name)
        field_name = field_name.to_s.downcase.gsub(/\s+/, '_')
        field_def = CustomFieldDefinition.find_by(entity: entity, model_type: model_type, field_name: field_name)

        return error_response("Custom field '#{field_name}' not found on #{model_type}") unless field_def

        field_def.update!(active: false)

        success_response(
          field_name: field_name,
          model: model_type,
          message: "Custom field '#{field_name}' removed from #{model_type}"
        )
      end

      def list_custom_fields(model_type)
        fields = CustomFieldDefinition.where(entity: entity, model_type: model_type, active: true).ordered

        success_response(
          model: model_type,
          fields: fields.map { |f|
            {
              id: f.id,
              name: f.field_name,
              type: f.field_type,
              label: f.label,
              required: f.required?,
              options: f.option_values
            }
          },
          count: fields.length,
          message: "#{fields.length} custom field(s) on #{model_type}"
        )
      end
    end
  end
end
