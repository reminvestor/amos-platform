# frozen_string_literal: true

module Tools
  # DiagnoseModuleTool - Checks module configuration health and identifies issues
  #
  # This tool enables self-healing by allowing Amos to diagnose problems with
  # modules, identify misconfigurations, and understand what needs to be fixed.
  #
  class DiagnoseModuleTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: "diagnose_module",
        description: "Diagnoses a custom module to identify configuration issues, missing fields, sync problems between schema and canvases, and other common problems. Use this before attempting to fix module issues.",
        category: "module_building",
        input_schema: {
          type: "object",
          properties: {
            module_slug: {
              type: "string",
              description: "The slug of the module to diagnose"
            },
            check_type: {
              type: "string",
              enum: ["full", "schema", "canvases", "database", "references"],
              description: "Type of check to perform. Default is 'full' for comprehensive diagnosis."
            }
          },
          required: ["module_slug"]
        }
      }
    end

    SUPPORTED_FIELD_TYPES = %w[string text integer decimal boolean date datetime json enum select reference].freeze
    REFERENCEABLE_MODELS = %w[LandingPage Contact Campaign User EmailTemplate Opportunity].freeze

    def execute(args)
      log_execution(args)
      module_slug = get_arg(args, :module_slug)
      check_type = get_arg(args, :check_type) || 'full'
      
      if error = validate_required_args(args, [:module_slug])
        return error
      end

      app_module = AppModule.find_by(slug: module_slug, entity_id: entity.id)
      unless app_module
        return error_response(
          "Module not found: #{module_slug}",
          available_modules: entity.app_modules.pluck(:slug, :name).map { |s, n| { slug: s, name: n } }
        )
      end

      issues = []
      warnings = []
      info = []

      case check_type
      when 'full'
        check_schema(app_module, issues, warnings, info)
        check_canvases(app_module, issues, warnings, info)
        check_database(app_module, issues, warnings, info)
        check_references(app_module, issues, warnings, info)
        check_sync(app_module, issues, warnings, info)
      when 'schema'
        check_schema(app_module, issues, warnings, info)
      when 'canvases'
        check_canvases(app_module, issues, warnings, info)
      when 'database'
        check_database(app_module, issues, warnings, info)
      when 'references'
        check_references(app_module, issues, warnings, info)
      end

      health_status = if issues.any?
        'unhealthy'
      elsif warnings.any?
        'degraded'
      else
        'healthy'
      end

      success_response(
        module_slug: app_module.slug,
        module_name: app_module.name,
        health_status: health_status,
        issues: issues,
        warnings: warnings,
        info: info,
        recommendations: generate_recommendations(issues, warnings),
        summary: generate_summary(app_module, issues, warnings)
      )
    end

    private

    def check_schema(app_module, issues, warnings, info)
      schema_fields = app_module.metadata&.dig('schema', 'fields') || []
      
      if schema_fields.empty?
        issues << {
          type: 'missing_schema',
          message: "Module has no schema fields defined",
          fix: "Use propose_module_schema to define fields"
        }
        return
      end

      info << "Schema has #{schema_fields.length} fields defined"

      schema_fields.each do |field|
        field_name = field['name']
        field_type = field['field_type'] || field['type']

        # Check for missing field_type
        if field_type.blank?
          issues << {
            type: 'missing_field_type',
            field: field_name,
            message: "Field '#{field_name}' has no field_type specified",
            fix: "Add field_type to the field definition"
          }
          next
        end

        # Check for unsupported field type
        unless SUPPORTED_FIELD_TYPES.include?(field_type.to_s.downcase)
          warnings << {
            type: 'unsupported_field_type',
            field: field_name,
            field_type: field_type,
            message: "Field '#{field_name}' has unsupported type '#{field_type}'",
            supported: SUPPORTED_FIELD_TYPES
          }
        end

        # Check reference fields
        if field_type.to_s.downcase == 'reference'
          ref_model = field['reference_model'] || field['references']
          if ref_model.blank?
            issues << {
              type: 'missing_reference_model',
              field: field_name,
              message: "Reference field '#{field_name}' has no reference_model specified",
              fix: "Add reference_model (e.g., 'LandingPage') to the field definition"
            }
          elsif !model_exists?(ref_model)
            warnings << {
              type: 'unknown_reference_model',
              field: field_name,
              reference_model: ref_model,
              message: "Reference model '#{ref_model}' may not exist",
              known_models: REFERENCEABLE_MODELS
            }
          end
        end

        # Check enum fields
        if %w[enum select].include?(field_type.to_s.downcase)
          options = field['options']
          if options.blank? || !options.is_a?(Array) || options.empty?
            issues << {
              type: 'missing_enum_options',
              field: field_name,
              message: "Enum field '#{field_name}' has no options defined",
              fix: "Add options array to the field definition"
            }
          end
        end

        # Check for _id fields that might need to be references
        if field_name.to_s.end_with?('_id') && field_type.to_s.downcase != 'reference'
          warnings << {
            type: 'possible_reference_field',
            field: field_name,
            current_type: field_type,
            message: "Field '#{field_name}' ends with _id but is not a reference type",
            suggestion: "Consider changing field_type to 'reference' with appropriate reference_model"
          }
        end
      end
    end

    def check_canvases(app_module, issues, warnings, info)
      canvases = app_module.module_canvases
      
      if canvases.empty?
        issues << {
          type: 'no_canvases',
          message: "Module has no canvases defined",
          fix: "Re-run approve_module_design to create canvases"
        }
        return
      end

      info << "Module has #{canvases.count} canvases: #{canvases.pluck(:canvas_type).join(', ')}"

      # Check for form canvas
      form_canvas = canvases.find_by(canvas_type: 'form')
      if form_canvas
        check_form_canvas(app_module, form_canvas, issues, warnings, info)
      else
        warnings << {
          type: 'missing_form_canvas',
          message: "Module has no form canvas - users cannot create/edit records in the UI"
        }
      end

      # Check for list canvas
      list_canvas = canvases.find_by(canvas_type: 'list')
      if list_canvas
        check_list_canvas(app_module, list_canvas, issues, warnings, info)
      end
    end

    def check_form_canvas(app_module, form_canvas, issues, warnings, info)
      schema_fields = app_module.metadata&.dig('schema', 'fields') || []
      canvas_fields = form_canvas.metadata&.dig('fields') || []
      
      schema_field_names = schema_fields.map { |f| f['name'] }
      canvas_field_names = canvas_fields.map { |f| f['name'] }

      missing_in_canvas = schema_field_names - canvas_field_names
      extra_in_canvas = canvas_field_names - schema_field_names

      if missing_in_canvas.any?
        issues << {
          type: 'fields_missing_from_canvas',
          canvas: 'form',
          missing_fields: missing_in_canvas,
          message: "#{missing_in_canvas.length} fields in schema are missing from form canvas: #{missing_in_canvas.join(', ')}",
          fix: "Use update_module with action: 'update_canvas' to sync fields to canvas metadata"
        }
      end

      if extra_in_canvas.any?
        warnings << {
          type: 'extra_fields_in_canvas',
          canvas: 'form',
          extra_fields: extra_in_canvas,
          message: "Form canvas has fields not in schema: #{extra_in_canvas.join(', ')}"
        }
      end

      # Check canvas field definitions
      canvas_fields.each do |field|
        field_name = field['name']
        field_type = field['field_type'] || field['type']
        
        if field_type.blank?
          warnings << {
            type: 'canvas_field_missing_type',
            canvas: 'form',
            field: field_name,
            message: "Form canvas field '#{field_name}' has no field_type - may render incorrectly"
          }
        end

        if field_type.to_s.downcase == 'reference' && field['reference_model'].blank? && field['references'].blank?
          issues << {
            type: 'canvas_reference_missing_model',
            canvas: 'form',
            field: field_name,
            message: "Form canvas reference field '#{field_name}' has no reference_model - dropdown will be empty"
          }
        end
      end
    end

    def check_list_canvas(app_module, list_canvas, issues, warnings, info)
      display_fields = list_canvas.metadata&.dig('display_fields') || list_canvas.columns || []
      
      if display_fields.empty?
        warnings << {
          type: 'no_display_fields',
          canvas: 'list',
          message: "List canvas has no display_fields - may show all fields or none"
        }
      else
        info << "List canvas displays #{display_fields.length} fields: #{display_fields.take(5).join(', ')}#{display_fields.length > 5 ? '...' : ''}"
      end
    end

    def check_database(app_module, issues, warnings, info)
      model_code = app_module.module_codes.find_by(code_type: 'model')
      
      unless model_code
        issues << {
          type: 'no_model_code',
          message: "Module has no model code - database table may not exist",
          fix: "Re-run approve_module_design or use update_module with action: 'regenerate_model'"
        }
        return
      end

      schema_definition = model_code.schema_definition || {}
      columns = schema_definition['columns'] || []
      table_name = schema_definition['table_name'] || app_module.slug.pluralize

      if columns.empty?
        warnings << {
          type: 'empty_schema_definition',
          message: "Model code has no columns defined in schema_definition"
        }
      end

      # Check if table exists
      begin
        if ActiveRecord::Base.connection.table_exists?(table_name)
          actual_columns = ActiveRecord::Base.connection.columns(table_name).map(&:name)
          info << "Database table '#{table_name}' exists with #{actual_columns.length} columns"

          # Compare schema fields to actual columns
          schema_fields = app_module.metadata&.dig('schema', 'fields') || []
          expected_columns = schema_fields.map { |f| f['name'] } + ['id', 'entity_id', 'created_at', 'updated_at']
          
          missing_columns = expected_columns - actual_columns
          if missing_columns.any?
            issues << {
              type: 'missing_database_columns',
              table: table_name,
              missing: missing_columns,
              message: "Database table missing columns: #{missing_columns.join(', ')}",
              fix: "Use update_module with action: 'regenerate_model' to update the table"
            }
          end
        else
          issues << {
            type: 'table_not_found',
            table: table_name,
            message: "Database table '#{table_name}' does not exist",
            fix: "The module may need to be re-deployed or the migration needs to run"
          }
        end
      rescue => e
        warnings << {
          type: 'database_check_error',
          message: "Could not check database: #{e.message}"
        }
      end
    end

    def check_references(app_module, issues, warnings, info)
      schema_fields = app_module.metadata&.dig('schema', 'fields') || []
      reference_fields = schema_fields.select { |f| (f['field_type'] || f['type']).to_s.downcase == 'reference' }
      
      if reference_fields.empty?
        info << "Module has no reference fields"
        return
      end

      info << "Module has #{reference_fields.length} reference fields"

      reference_fields.each do |field|
        field_name = field['name']
        ref_model = field['reference_model'] || field['references']

        if ref_model.present?
          # Try to count records
          begin
            model_class = ref_model.to_s.classify.constantize
            count = if model_class.column_names.include?('entity_id')
              model_class.where(entity_id: entity.id).count
            else
              model_class.count
            end

            if count == 0
              warnings << {
                type: 'empty_reference_model',
                field: field_name,
                reference_model: ref_model,
                message: "Reference model '#{ref_model}' has no records - dropdown will be empty"
              }
            else
              info << "Field '#{field_name}' references #{ref_model} with #{count} available records"
            end
          rescue NameError
            issues << {
              type: 'invalid_reference_model',
              field: field_name,
              reference_model: ref_model,
              message: "Reference model '#{ref_model}' does not exist as a class",
              known_models: REFERENCEABLE_MODELS
            }
          rescue => e
            warnings << {
              type: 'reference_check_error',
              field: field_name,
              message: "Could not check reference: #{e.message}"
            }
          end
        end
      end
    end

    def check_sync(app_module, issues, warnings, info)
      schema_fields = app_module.metadata&.dig('schema', 'fields') || []
      form_canvas = app_module.module_canvases.find_by(canvas_type: 'form')
      canvas_fields = form_canvas&.metadata&.dig('fields') || []

      # Deep check: Are the field definitions the same?
      schema_fields.each do |schema_field|
        canvas_field = canvas_fields.find { |f| f['name'] == schema_field['name'] }
        next unless canvas_field

        schema_type = schema_field['field_type'] || schema_field['type']
        canvas_type = canvas_field['field_type'] || canvas_field['type']

        if schema_type != canvas_type
          warnings << {
            type: 'field_type_mismatch',
            field: schema_field['name'],
            schema_type: schema_type,
            canvas_type: canvas_type,
            message: "Field '#{schema_field['name']}' has type mismatch: schema='#{schema_type}', canvas='#{canvas_type}'"
          }
        end

        if schema_type.to_s.downcase == 'reference'
          schema_ref = schema_field['reference_model'] || schema_field['references']
          canvas_ref = canvas_field['reference_model'] || canvas_field['references']
          
          if schema_ref != canvas_ref
            issues << {
              type: 'reference_model_mismatch',
              field: schema_field['name'],
              schema_ref: schema_ref,
              canvas_ref: canvas_ref,
              message: "Field '#{schema_field['name']}' has reference_model mismatch"
            }
          end
        end
      end
    end

    def model_exists?(model_name)
      model_name.to_s.classify.constantize
      true
    rescue NameError
      false
    end

    def generate_recommendations(issues, warnings)
      recommendations = []

      if issues.any? { |i| i[:type] == 'fields_missing_from_canvas' }
        recommendations << {
          action: "Sync fields to canvas",
          tool: "update_module",
          params: { action: "update_canvas", canvas_slug: "form" },
          priority: "high"
        }
      end

      if issues.any? { |i| i[:type] == 'missing_reference_model' }
        recommendations << {
          action: "Add reference_model to reference fields",
          tool: "update_module", 
          params: { action: "update_field" },
          priority: "high"
        }
      end

      if issues.any? { |i| i[:type] == 'missing_database_columns' }
        recommendations << {
          action: "Regenerate model to add missing columns",
          tool: "update_module",
          params: { action: "regenerate_model" },
          priority: "high"
        }
      end

      if warnings.any? { |w| w[:type] == 'possible_reference_field' }
        recommendations << {
          action: "Review _id fields - may need to be reference type",
          tool: "update_module",
          params: { action: "update_field" },
          priority: "medium"
        }
      end

      recommendations
    end

    def generate_summary(app_module, issues, warnings)
      if issues.empty? && warnings.empty?
        "✅ Module '#{app_module.name}' is healthy - no issues detected"
      elsif issues.empty?
        "⚠️ Module '#{app_module.name}' has #{warnings.length} warning(s) but should work"
      else
        "❌ Module '#{app_module.name}' has #{issues.length} issue(s) that need to be fixed"
      end
    end
  end
end





