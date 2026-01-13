# frozen_string_literal: true

module Tools
  # RepairModuleTool - Fixes broken or incomplete module installations
  #
  # This tool can:
  # 1. Re-build modules that have no schema
  # 2. Re-create database tables that are missing
  # 3. Re-generate canvases that weren't created
  #
  class RepairModuleTool < BaseTool
    def self.metadata
      {
        name: "repair_module",
        description: <<~DESC.strip,
          Repairs a broken or incomplete module installation.
          Use this when a module exists but:
          - Has no schema/fields defined
          - Has no database table
          - Has no canvases
          - Is stuck in 'building' or 'draft' status
          
          This will attempt to rebuild the missing components.
        DESC
        category: "module_building",
        input_schema: {
          type: "object",
          properties: {
            module_slug: {
              type: "string",
              description: "The slug of the module to repair"
            },
            repair_type: {
              type: "string",
              enum: ["full", "schema_only", "database_only", "canvases_only"],
              description: "Type of repair. 'full' attempts all repairs."
            }
          },
          required: ["module_slug"]
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      module_slug = get_arg(args, :module_slug)
      repair_type = get_arg(args, :repair_type, 'full')

      if error = validate_required_args(args, [:module_slug])
        return error
      end

      app_module = AppModule.find_by(slug: module_slug, entity_id: entity.id)
      unless app_module
        return error_response("Module not found: #{module_slug}")
      end

      repairs_made = []
      errors = []

      # Step 1: Check and repair schema
      if %w[full schema_only].include?(repair_type)
        if needs_schema_repair?(app_module)
          result = repair_schema(app_module)
          if result[:success]
            repairs_made << "Schema repaired with #{result[:field_count]} fields"
          else
            errors << "Schema repair failed: #{result[:error]}"
          end
        else
          repairs_made << "Schema OK (#{app_module.enhanced_fields&.count || 0} fields)"
        end
      end

      # Reload to get updated schema
      app_module.reload

      # Step 2: Check and repair database
      if %w[full database_only].include?(repair_type)
        if needs_database_repair?(app_module)
          result = repair_database(app_module)
          if result[:success]
            repairs_made << "Database table created: #{result[:table_name]}"
          else
            errors << "Database repair failed: #{result[:error]}"
          end
        else
          repairs_made << "Database OK"
        end
      end

      # Step 3: Check and repair canvases
      if %w[full canvases_only].include?(repair_type)
        if needs_canvas_repair?(app_module)
          result = repair_canvases(app_module)
          if result[:success]
            repairs_made << "Canvases created: #{result[:canvases].join(', ')}"
          else
            errors << "Canvas repair failed: #{result[:error]}"
          end
        else
          repairs_made << "Canvases OK (#{app_module.module_canvases.count} canvases)"
        end
      end

      # Activate the module if all repairs succeeded
      if errors.empty? && app_module.status != 'active'
        app_module.update!(status: 'active')
        repairs_made << "Module activated"
      end

      if errors.any?
        {
          success: false,
          module_slug: app_module.slug,
          repairs_made: repairs_made,
          errors: errors,
          message: "⚠️ Partial repair completed with errors"
        }
      else
        {
          success: true,
          module_slug: app_module.slug,
          repairs_made: repairs_made,
          message: "✅ Module '#{app_module.name}' repaired successfully!",
          canvas: "module_#{app_module.slug}_list",
          canvas_data: { module_slug: app_module.slug }
        }
      end
    end

    private

    def needs_schema_repair?(app_module)
      fields = app_module.enhanced_fields || []
      fields.empty?
    end

    def needs_database_repair?(app_module)
      model_code = app_module.module_codes.find_by(code_type: 'model')
      return true unless model_code

      table_name = app_module.slug.pluralize
      !ActiveRecord::Base.connection.table_exists?(table_name)
    rescue
      true
    end

    def needs_canvas_repair?(app_module)
      app_module.module_canvases.empty?
    end

    def repair_schema(app_module)
      # Get requirements from metadata or template
      requirements = app_module.metadata&.dig('requirements') ||
                     app_module.configuration&.dig('requirements') ||
                     get_template_requirements(app_module.slug)

      if requirements.blank?
        # Generate basic requirements from the module name/description
        requirements = "Build a #{app_module.name} with standard CRUD fields"
      end

      # Use AI to generate schema
      schema_result = generate_schema_with_ai(app_module.name, requirements)
      
      if schema_result[:error]
        return { success: false, error: schema_result[:error] }
      end

      fields = schema_result[:fields]

      # Update the module with the schema
      app_module.update!(
        metadata: app_module.metadata.merge(
          'schema' => {
            'fields' => fields,
            'module' => { 'name' => app_module.name, 'icon' => app_module.icon }
          }
        ),
        field_config: { 'fields' => fields }
      )

      { success: true, field_count: fields.count }
    end

    def repair_database(app_module)
      fields = app_module.enhanced_fields || []
      
      if fields.empty?
        return { success: false, error: "No fields defined - repair schema first" }
      end

      table_name = app_module.slug.pluralize

      # Build schema columns
      schema_columns = [
        { 'name' => 'id', 'type' => 'bigint', 'primary' => true },
        { 'name' => 'entity_id', 'type' => 'bigint', 'null' => false, 'index' => true }
      ]

      fields.each do |field|
        next if %w[id entity_id created_at updated_at].include?(field['name'])
        
        schema_columns << {
          'name' => field['name'],
          'type' => map_field_to_db_type(field['field_type'] || field['type']),
          'null' => !field['required']
        }
      end

      schema_columns += [
        { 'name' => 'created_at', 'type' => 'datetime', 'null' => false },
        { 'name' => 'updated_at', 'type' => 'datetime', 'null' => false }
      ]

      # Find or create ModuleCode
      model_code = app_module.module_codes.find_or_create_by!(code_type: 'model') do |mc|
        mc.entity = entity
        mc.name = app_module.slug.classify
        mc.status = 'pending'
      end

      model_code.update!(
        schema_definition: {
          'table_name' => table_name,
          'columns' => schema_columns
        },
        fields: fields.map { |f| { 'name' => f['name'], 'type' => f['field_type'] || f['type'] } },
        associations: [{ 'type' => 'belongs_to', 'model' => 'Entity' }]
      )

      # Create the table using DynamicModelLoader
      begin
        Modules::DynamicModelLoader.instance.load_model(model_code)
        model_code.mark_deployed!
        { success: true, table_name: table_name }
      rescue => e
        { success: false, error: e.message }
      end
    end

    def repair_canvases(app_module)
      fields = app_module.enhanced_fields || []
      created_canvases = []

      # Create list canvas
      unless app_module.module_canvases.exists?(canvas_type: 'list')
        list_canvas = app_module.module_canvases.create!(
          entity: entity,
          name: "#{app_module.name} List",
          slug: "list",
          canvas_type: 'list',
          is_default: true,
          metadata: {
            'display_fields' => fields.first(5).map { |f| f['name'] },
            'fields' => fields
          }
        )
        created_canvases << 'list'
      end

      # Create form canvas
      unless app_module.module_canvases.exists?(canvas_type: 'form')
        form_canvas = app_module.module_canvases.create!(
          entity: entity,
          name: "#{app_module.name} Form",
          slug: "form",
          canvas_type: 'form',
          metadata: {
            'fields' => fields.map do |f|
              {
                'name' => f['name'],
                'label' => f['label'] || f['name'].titleize,
                'field_type' => f['field_type'] || f['type'] || 'string',
                'required' => f['required'] || false
              }
            end
          }
        )
        created_canvases << 'form'
      end

      { success: true, canvases: created_canvases }
    end

    def generate_schema_with_ai(module_name, requirements)
      system_prompt = <<~PROMPT
        You are a database schema designer. Generate a schema for a module.
        
        Return a JSON array of fields, each with:
        - name: lowercase_with_underscores
        - label: Human Readable Label
        - field_type: one of [string, text, integer, decimal, boolean, date, datetime, select, reference]
        - required: true/false
        - options: array (only for select type)
        
        Include standard fields like name/title, description, status, etc.
        Return ONLY the JSON array, no explanation.
      PROMPT

      user_prompt = "Generate schema for: #{module_name}\n\nRequirements: #{requirements}"

      begin
        service = BedrockLlmService.new(model: 'qwen-3-32b')
        response = service.chat(
          messages: [{ role: 'user', content: user_prompt }],
          system_prompt: system_prompt,
          max_tokens: 2000
        )

        json_match = response[:content]&.match(/\[[\s\S]*\]/)
        if json_match
          fields = JSON.parse(json_match[0])
          { success: true, fields: fields }
        else
          { error: "Could not parse AI response" }
        end
      rescue => e
        { error: e.message }
      end
    end

    def get_template_requirements(slug)
      template = Modules::TemplateInstaller::TEMPLATES[slug]
      template&.dig(:requirements)
    end

    def map_field_to_db_type(field_type)
      case field_type.to_s.downcase
      when 'string', 'select', 'enum', 'reference' then 'string'
      when 'text' then 'text'
      when 'integer', 'number' then 'integer'
      when 'decimal', 'float', 'money' then 'decimal'
      when 'boolean' then 'boolean'
      when 'date' then 'date'
      when 'datetime', 'timestamp' then 'datetime'
      when 'json', 'object', 'array' then 'jsonb'
      else 'string'
      end
    end
  end
end


