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
            - Add custom field: type="schema", id="contact", data={ add_field: { name: "industry", field_type: "string" } }
            - Remove custom field: type="schema", id="contact", data={ remove_field: "industry" }
            
            For app modules, use type="app_module" to update the module itself (name, description, schema fields, icon, etc.).
            To update records WITHIN a module, use the module's slug as the type (e.g., type="project_tracker", id=5, data={...}).
            
            Examples:
            - type: "contact", id: 42, data: { lifecycle_stage: "customer" }
            - type: "app_module", id: 7, data: { name: "New Name", schema: { fields: [{ name: "priority", type: "select", options: ["low", "medium", "high"] }] } }
            - type: "landing_page", id: 189, data: { section: "hero", instruction: "Center the text" }
            - type: "landing_page", id: 189, data: { instruction: "Redesign with a dark theme and bold typography" }
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              type: {
                type: "string",
                description: "Object type to update (contact, campaign, landing_page, email_template, app_module, etc.)"
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

        # Landing page with instruction but no section — the model wants to regenerate/restyle
        # the entire page. Route to GenerateLandingPageTool as an update.
        if type == "landing_page" && (data["instruction"] || data[:instruction])
          return regenerate_landing_page(id, data)
        end

        # App module / module update — update the AppModule record itself
        if %w[app_module app module].include?(type)
          return update_app_module(id, data)
        end

        # Check if type matches a dynamic module model
        module_result = find_and_update_module_record(type, id, data)
        return module_result if module_result

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

      # ═══════════════════════════════════════════════════════════════
      # APP MODULE UPDATES — update the AppModule record itself
      # ═══════════════════════════════════════════════════════════════

      def update_app_module(id, data)
        # Find by ID or slug
        app_module = entity.app_modules.find_by(id: id) ||
                     entity.app_modules.find_by(slug: id.to_s)

        return error_response("App module ##{id} not found") unless app_module

        Rails.logger.info "[V3::PlatformUpdate] Updating app module: #{app_module.name} (##{app_module.id})"

        updated_fields = []

        # Direct attribute updates
        direct_attrs = %w[name description icon status version show_in_menu menu_order menu_parent]
        direct_updates = data.select { |k, _| direct_attrs.include?(k.to_s) }
        if direct_updates.any?
          app_module.assign_attributes(direct_updates)
          updated_fields.concat(direct_updates.keys.map(&:to_s))
        end

        # Schema updates — merge new/changed fields into the existing schema
        new_schema = data["schema"] || data[:schema]
        if new_schema.is_a?(Hash)
          existing_schema = app_module.metadata&.dig("schema") || {}
          new_fields = new_schema["fields"] || new_schema[:fields]

          if new_fields.is_a?(Array)
            existing_fields = existing_schema["fields"] || []

            new_fields.each do |new_field|
              field_name = new_field["name"] || new_field[:name]
              existing_idx = existing_fields.index { |f| (f["name"] || f[:name]) == field_name }
              if existing_idx
                # Merge into existing field definition
                existing_fields[existing_idx] = existing_fields[existing_idx].merge(new_field.stringify_keys)
              else
                # Add new field
                existing_fields << new_field.stringify_keys
              end
            end

            existing_schema["fields"] = existing_fields
          end

          # Merge any other schema-level keys (e.g., module name, description)
          merged_schema = existing_schema.merge(new_schema.stringify_keys.except("fields"))
          merged_schema["fields"] = existing_schema["fields"] if existing_schema["fields"]

          app_module.metadata = (app_module.metadata || {}).merge("schema" => merged_schema)
          updated_fields << "schema"
        end

        # Metadata updates (non-schema)
        new_metadata = data["metadata"] || data[:metadata]
        if new_metadata.is_a?(Hash)
          app_module.metadata = (app_module.metadata || {}).merge(new_metadata.stringify_keys)
          updated_fields << "metadata"
        end

        # Components updates
        new_components = data["components"] || data[:components]
        if new_components.is_a?(Hash)
          app_module.components = (app_module.components || {}).merge(new_components.stringify_keys)
          updated_fields << "components"
        end

        return error_response("No valid fields to update for app module") if updated_fields.empty?

        app_module.save!

        # Return module info with canvas suggestion so the user sees their module
        default_canvas = app_module.module_canvases.find_by(is_default: true)
        canvas_slug = default_canvas ? "module_#{default_canvas.slug}" : nil

        success_response(
          id: app_module.id,
          type: "app_module",
          name: app_module.name,
          slug: app_module.slug,
          status: app_module.status,
          updated_fields: updated_fields,
          message: "Updated app '#{app_module.name}' (#{updated_fields.join(', ')})",
          canvas_type: canvas_slug,
          canvas_data: { app_module_id: app_module.id }
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("Validation failed: #{e.message}")
      rescue => e
        Rails.logger.error "[V3::PlatformUpdate] App module update failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Failed to update app module: #{e.message}")
      end

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

      # When the model provides an instruction without a section, it wants to regenerate
      # the entire landing page with new content/style. We re-run the generator on the
      # existing page, treating the instruction + any other data fields as the new spec.
      def regenerate_landing_page(landing_page_id, data)
        lp = LandingPage.find_by(id: landing_page_id, entity: entity)
        return error_response("Landing page ##{landing_page_id} not found") unless lp

        instruction = data["instruction"] || data[:instruction]
        description = data["description"] || data[:description] || lp.description

        Rails.logger.info "[V3::PlatformUpdate] Regenerating landing page ##{landing_page_id} with instruction: #{instruction.to_s.truncate(100)}"

        # Build generation args from existing page + new instructions
        gen_args = {
          "title" => lp.title,
          "description" => "#{description}\n\nAdditional instructions: #{instruction}",
          "page_type" => "lead_generation"
        }

        # Pass through any extra design/content keys the model provided
        %w[theme brand_voice color_scheme sections key_details business_info design_preferences
           headline cta_text tone_of_voice aesthetic_style layout_preference].each do |key|
          val = data[key] || data[key.to_sym]
          gen_args[key] = val if val.present?
        end

        generator = ::Tools::GenerateLandingPageTool.new(
          user: user,
          entity: entity,
          context: context
        )

        # Generate new HTML
        result = generator.execute(gen_args)

        # If generation succeeded, update the existing landing page with the new HTML
        if result.is_a?(Hash) && result[:success] != false
          new_page_id = result[:landing_page_id] || result[:id]

          # If the generator created a NEW page, copy its HTML to the original and delete the new one
          if new_page_id && new_page_id != landing_page_id
            new_page = LandingPage.find_by(id: new_page_id)
            if new_page
              lp.update!(
                html_content: new_page.html_content,
                description: description
              )
              new_page.destroy
            end
          end

          @context[:canvas_suggestion] = "landing_page_editor"

          success_response(
            id: lp.id,
            title: lp.title,
            message: "Landing page '#{lp.title}' has been regenerated with your instructions.",
            canvas_type: "landing_page_editor",
            canvas_data: { landing_page_id: lp.id }
          )
        else
          result
        end
      rescue => e
        Rails.logger.error "[V3::PlatformUpdate] Landing page regeneration failed: #{e.message}"
        error_response("Failed to regenerate landing page: #{e.message}")
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

        # Batch: add_fields (plural) — create many fields in one call
        if data["add_fields"] || data[:add_fields]
          fields_array = data["add_fields"] || data[:add_fields]
          return batch_add_custom_fields(model_type, fields_array)
        elsif data["add_field"] || data[:add_field]
          add_custom_field(model_type, data["add_field"] || data[:add_field])
        elsif data["remove_field"] || data[:remove_field]
          remove_custom_field(model_type, data["remove_field"] || data[:remove_field])
        elsif data["list_fields"] || data[:list_fields]
          list_custom_fields(model_type)
        else
          error_response("Specify add_field, add_fields (batch), remove_field, or list_fields")
        end
      end

      # Batch add multiple custom fields in one tool call (turns 26 calls into 1)
      def batch_add_custom_fields(model_type, fields_array)
        return error_response("add_fields must be an array") unless fields_array.is_a?(Array)

        created = 0
        already_existed = 0
        failed = []

        fields_array.each_with_index do |field_data, idx|
          result = add_custom_field(model_type, field_data)
          if result.is_a?(Hash) && result[:success] != false
            if result.dig(:data, :already_exists)
              already_existed += 1
            else
              created += 1
            end
          else
            error_msg = result.is_a?(Hash) ? (result[:error] || result.dig(:data, :error)) : result.to_s
            failed << { index: idx, name: field_data[:name] || field_data["name"], error: error_msg }
          end
        end

        summary = "#{created} fields created"
        summary += ", #{already_existed} already existed" if already_existed > 0
        summary += ", #{failed.length} failed" if failed.any?

        Rails.logger.info "[V3::PlatformUpdate] Batch custom fields on #{model_type}: #{summary}"

        success_response(
          model: model_type,
          batch: true,
          total: fields_array.length,
          created: created,
          already_existed: already_existed,
          failed: failed.length,
          errors: failed.first(5),
          message: "Custom fields on #{model_type}: #{summary}"
        )
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

        sanitized_name = name.downcase.gsub(/\s+/, '_')

        # Idempotent: if same field already exists with same type, return success
        existing = CustomFieldDefinition.find_by(entity: entity, model_type: model_type, field_name: sanitized_name)
        if existing
          if existing.field_type == field_type
            Rails.logger.info "[V3::PlatformUpdate] Custom field '#{name}' already exists on #{model_type} — idempotent success"
            return success_response(
              field_id: existing.id,
              model: model_type,
              field_name: existing.field_name,
              field_type: existing.field_type,
              label: existing.label,
              already_exists: true,
              message: "Custom field '#{existing.label}' already exists on #{model_type} (same type: #{field_type}). No action needed."
            )
          else
            return error_response(
              "Custom field '#{name}' already exists on #{model_type} with type '#{existing.field_type}' (requested: '#{field_type}'). " \
              "Remove the existing field first if you need to change the type."
            )
          end
        end

        # Auto-correct invalid field types to nearest valid type
        unless CustomFieldDefinition::FIELD_TYPES.include?(field_type)
          corrected = case field_type.downcase
                      when "number", "int", "float", "numeric" then "integer"
                      when "bool", "checkbox", "toggle" then "boolean"
                      when "datetime", "timestamp" then "datetime"
                      when "list", "multi", "multiselect", "tags" then "array"
                      when "object", "hash", "map", "struct" then "json"
                      when "textarea", "longtext", "memo" then "text"
                      when "ref", "belongs_to", "link", "foreign_key" then "reference"
                      else "string"
                      end
          Rails.logger.info "[V3::PlatformUpdate] Auto-corrected field type '#{field_type}' → '#{corrected}' for '#{name}'"
          field_type = corrected
        end

        field_def = CustomFieldDefinition.create!(
          entity: entity,
          model_type: model_type,
          field_name: sanitized_name,
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
      rescue ActiveRecord::RecordInvalid => e
        error_response(
          "Failed to add custom field '#{name}': #{e.message}. " \
          "Valid field_type values: #{CustomFieldDefinition::FIELD_TYPES.join(', ')}"
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

      # ═══════════════════════════════════════════════════════════════
      # DYNAMIC MODULE UPDATES
      # ═══════════════════════════════════════════════════════════════

      def find_and_update_module_record(type, id, data)
        model_class = resolve_dynamic_model(type)
        return nil unless model_class

        Rails.logger.info "[V3::PlatformUpdate] Updating dynamic module record: #{type} ##{id}"

        record = model_class.find_by(id: id, entity_id: entity.id)
        return error_response("#{type.titleize} ##{id} not found") unless record

        # Filter data to only include valid columns
        valid_columns = model_class.column_names - %w[id entity_id created_at updated_at]
        update_data = data.select { |k, _| valid_columns.include?(k.to_s) }

        return error_response("No valid fields to update") if update_data.empty?

        record.update!(update_data)

        success_response(
          id: record.id,
          type: type,
          updated_fields: update_data.keys,
          record: record.attributes.except('entity_id'),
          message: "Updated #{type.titleize} ##{id} (#{update_data.keys.join(', ')})"
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("Validation failed: #{e.message}")
      rescue => e
        Rails.logger.error "[V3::PlatformUpdate] Dynamic module update failed: #{e.message}"
        error_response("Failed to update #{type} ##{id}: #{e.message}")
      end

      def resolve_dynamic_model(type)
        return nil unless entity

        # Strategy 1: "module_slug/ModelName" format
        if type.include?('/')
          parts = type.split('/')
          app_module = entity.app_modules.active.find_by(slug: parts[0])
          return nil unless app_module
          return Modules::DynamicModelLoader.instance.get_model(app_module, parts[1].classify)
        end

        # Strategy 2: Direct slug match
        app_module = entity.app_modules.active.find_by(slug: type) ||
                     entity.app_modules.active.find_by(slug: type.singularize)
        if app_module
          model_class = Modules::DynamicModelLoader.instance.get_model(app_module, app_module.slug.classify)
          return model_class if model_class
        end

        # Strategy 3: Check sub-module slugs and model names
        entity.app_modules.active.each do |mod|
          mod.module_codes.where(code_type: 'model').each do |model_code|
            model_name = model_code.name
            if model_name.underscore == type || model_name.underscore == type.singularize ||
               model_name.underscore.pluralize == type
              return Modules::DynamicModelLoader.instance.get_model(mod, model_name)
            end
            table = model_code.schema_definition&.dig('table_name')
            if table == type.pluralize || table == type
              return Modules::DynamicModelLoader.instance.get_model(mod, model_name)
            end
          end
        end

        nil
      end
    end
  end
end
