# frozen_string_literal: true

# ModuleExporter
#
# Exports a module's configuration and code for backup or sharing.
#
module Modules
  class ModuleExporter
    def initialize(app_module)
      @app_module = app_module
    end

    def export
      {
        format_version: '1.0',
        exported_at: Time.current.iso8601,
        module: export_module_metadata,
        canvases: export_canvases,
        models: export_models,
        tools: export_tools,
        webhooks: export_webhooks,
        custom_fields: export_custom_fields
      }
    end

    def to_json
      export.to_json
    end

    private

    def export_module_metadata
      {
        slug: @app_module.slug,
        name: @app_module.name,
        description: @app_module.description,
        version: @app_module.version,
        icon: @app_module.icon,
        author_type: @app_module.author_type,
        components: @app_module.components,
        ui_modes: @app_module.ui_modes,
        dependencies: @app_module.dependencies,
        permissions: @app_module.permissions,
        show_in_menu: @app_module.show_in_menu,
        menu_order: @app_module.menu_order,
        metadata: @app_module.metadata
      }
    end

    def export_canvases
      @app_module.module_canvases.map do |canvas|
        {
          slug: canvas.slug,
          name: canvas.name,
          description: canvas.description,
          canvas_type: canvas.canvas_type,
          ui_mode: canvas.ui_mode,
          html_content: canvas.html_content,
          js_content: canvas.js_content,
          css_content: canvas.css_content,
          data_sources: canvas.data_sources,
          actions: canvas.actions,
          layout_config: canvas.layout_config,
          is_default: canvas.is_default,
          metadata: canvas.metadata
        }
      end
    end

    def export_models
      @app_module.module_codes.models.map do |model_code|
        {
          name: model_code.name,
          code_type: model_code.code_type,
          content: model_code.content,
          schema_definition: model_code.schema_definition,
          metadata: model_code.metadata
        }
      end
    end

    def export_tools
      @app_module.tool_definitions.map do |tool|
        {
          name: tool.name,
          description: tool.description,
          parameters: tool.parameters,
          execution_type: tool.execution_type,
          code: tool.code,
          api_config: tool.api_config&.except('auth_token', 'signing_secret'),
          admin_only: tool.admin_only,
          scout_accessible: tool.scout_accessible
        }
      end
    end

    def export_webhooks
      @app_module.module_webhooks.map do |webhook|
        {
          slug: webhook.slug,
          event_name: webhook.event_name,
          description: webhook.description,
          auth_type: webhook.auth_type,
          payload_schema: webhook.payload_schema,
          field_mappings: webhook.field_mappings,
          target_type: webhook.target_type,
          target_tool: webhook.target_tool,
          context_template: webhook.context_template,
          rate_limit_per_minute: webhook.rate_limit_per_minute,
          rate_limit_per_hour: webhook.rate_limit_per_hour,
          metadata: webhook.metadata
        }
      end
    end

    def export_custom_fields
      @app_module.custom_field_definitions.map do |field|
        {
          model_type: field.model_type,
          field_name: field.field_name,
          field_type: field.field_type,
          field_label: field.field_label,
          field_description: field.field_description,
          display_type: field.display_type,
          display_order: field.display_order,
          show_in_list: field.show_in_list,
          show_in_form: field.show_in_form,
          show_in_search: field.show_in_search,
          options: field.options,
          validations: field.validations,
          default_value: field.default_value,
          reference_model: field.reference_model,
          reference_display_field: field.reference_display_field,
          metadata: field.metadata
        }
      end
    end
  end
end





