# frozen_string_literal: true

# ModuleImporter
#
# Imports a module from an exported configuration.
#
module Modules
  class ModuleImporter
    def initialize(entity:, user:, export_data:)
      @entity = entity
      @user = user
      @data = export_data.deep_symbolize_keys
    end

    def import
      validate!
      
      ActiveRecord::Base.transaction do
        @app_module = create_module
        import_canvases
        import_models
        import_tools
        import_webhooks
        import_custom_fields
      end

      {
        success: true,
        module: @app_module,
        module_slug: @app_module.slug,
        components: {
          canvases: @app_module.module_canvases.count,
          models: @app_module.module_codes.models.count,
          tools: @app_module.tool_definitions.count,
          webhooks: @app_module.module_webhooks.count,
          custom_fields: @app_module.custom_field_definitions.count
        }
      }
    rescue => e
      { success: false, error: e.message }
    end

    private

    def validate!
      raise 'Invalid export format' unless @data[:module].present?
      raise 'Missing module slug' unless @data[:module][:slug].present?
      raise 'Missing module name' unless @data[:module][:name].present?
    end

    def create_module
      module_data = @data[:module]
      
      # Ensure unique slug
      slug = module_data[:slug]
      counter = 1
      while AppModule.exists?(entity: @entity, slug: slug)
        slug = "#{module_data[:slug]}_#{counter}"
        counter += 1
      end

      AppModule.create!(
        entity: @entity,
        created_by: @user,
        slug: slug,
        name: module_data[:name],
        description: module_data[:description],
        version: module_data[:version] || '1.0.0',
        icon: module_data[:icon],
        status: 'draft',
        author_type: 'user',  # Imported modules are user-owned
        visibility: 'entity_private',
        components: module_data[:components] || {},
        ui_modes: module_data[:ui_modes] || { 'simple' => true },
        dependencies: module_data[:dependencies] || [],
        permissions: module_data[:permissions] || [],
        show_in_menu: module_data[:show_in_menu] != false,
        menu_order: module_data[:menu_order] || 100,
        metadata: (module_data[:metadata] || {}).merge(
          'imported_at' => Time.current.iso8601,
          'imported_version' => @data[:format_version]
        )
      )
    end

    def import_canvases
      (@data[:canvases] || []).each do |canvas_data|
        ModuleCanvas.create!(
          app_module: @app_module,
          entity: @entity,
          slug: canvas_data[:slug],
          name: canvas_data[:name],
          description: canvas_data[:description],
          canvas_type: canvas_data[:canvas_type] || 'module',
          ui_mode: canvas_data[:ui_mode] || 'simple',
          html_content: canvas_data[:html_content],
          js_content: canvas_data[:js_content],
          css_content: canvas_data[:css_content],
          data_sources: canvas_data[:data_sources] || [],
          actions: canvas_data[:actions] || [],
          layout_config: canvas_data[:layout_config] || {},
          is_default: canvas_data[:is_default] == true,
          metadata: canvas_data[:metadata] || {}
        )
      end
    end

    def import_models
      (@data[:models] || []).each do |model_data|
        ModuleCode.create!(
          app_module: @app_module,
          entity: @entity,
          name: model_data[:name],
          code_type: model_data[:code_type] || 'model',
          content: model_data[:content],
          schema_definition: model_data[:schema_definition] || {},
          status: 'generated',
          metadata: model_data[:metadata] || {}
        )
      end
    end

    def import_tools
      (@data[:tools] || []).each do |tool_data|
        ToolDefinition.create!(
          app_module: @app_module,
          entity: @entity,
          created_by: @user,
          name: "#{@app_module.slug}_#{tool_data[:name]}",  # Prefix to avoid conflicts
          description: tool_data[:description],
          parameters: tool_data[:parameters] || {},
          execution_type: tool_data[:execution_type] || 'ruby_code',
          code: tool_data[:code],
          api_config: tool_data[:api_config],
          admin_only: tool_data[:admin_only] == true,
          scout_accessible: tool_data[:scout_accessible] != false,
          is_public: false
        )
      end
    end

    def import_webhooks
      (@data[:webhooks] || []).each do |webhook_data|
        ModuleWebhook.create!(
          app_module: @app_module,
          entity: @entity,
          slug: "#{@app_module.slug}_#{webhook_data[:slug]}",
          event_name: webhook_data[:event_name],
          description: webhook_data[:description],
          auth_type: webhook_data[:auth_type] || 'token',
          payload_schema: webhook_data[:payload_schema] || {},
          field_mappings: webhook_data[:field_mappings] || {},
          target_type: webhook_data[:target_type] || 'tool',
          target_tool: webhook_data[:target_tool],
          context_template: webhook_data[:context_template] || {},
          rate_limit_per_minute: webhook_data[:rate_limit_per_minute] || 60,
          rate_limit_per_hour: webhook_data[:rate_limit_per_hour] || 1000,
          status: 'active',
          metadata: webhook_data[:metadata] || {}
        )
      end
    end

    def import_custom_fields
      (@data[:custom_fields] || []).each do |field_data|
        CustomFieldDefinition.create!(
          app_module: @app_module,
          entity: @entity,
          model_type: field_data[:model_type],
          field_name: field_data[:field_name],
          field_type: field_data[:field_type],
          field_label: field_data[:field_label],
          field_description: field_data[:field_description],
          display_type: field_data[:display_type] || 'text',
          display_order: field_data[:display_order] || 0,
          show_in_list: field_data[:show_in_list] != false,
          show_in_form: field_data[:show_in_form] != false,
          show_in_search: field_data[:show_in_search] == true,
          options: field_data[:options] || [],
          validations: field_data[:validations] || {},
          default_value: field_data[:default_value],
          reference_model: field_data[:reference_model],
          reference_display_field: field_data[:reference_display_field] || 'name',
          active: true,
          metadata: field_data[:metadata] || {}
        )
      end
    end
  end
end





