# frozen_string_literal: true

module Tools
  # Allows users to customize a module template before installation
  class CustomizeTemplateTool < BaseTool
    def self.metadata
      {
        name: 'customize_template',
        description: 'Customize a module template before installing it. ' \
                     'Lets users add, remove, or modify fields from the standard template.',
        category: 'module_building',
        input_schema: {
          type: 'object',
          properties: {
            template_key: {
              type: 'string',
              enum: %w[inventory_management project_management financial_tracking crm_extension 
                       property_management support_tickets employee_directory event_management 
                       subscription_billing knowledge_base],
              description: 'Which template to customize'
            },
            customizations: {
              type: 'object',
              properties: {
                add_fields: {
                  type: 'array',
                  items: {
                    type: 'object',
                    properties: {
                      name: { type: 'string' },
                      field_type: { type: 'string' },
                      required: { type: 'boolean' },
                      description: { type: 'string' }
                    }
                  },
                  description: 'New fields to add to the template'
                },
                remove_fields: {
                  type: 'array',
                  items: { type: 'string' },
                  description: 'Field names to remove from the template'
                },
                modify_fields: {
                  type: 'array',
                  items: {
                    type: 'object',
                    properties: {
                      name: { type: 'string' },
                      updates: { type: 'object' }
                    }
                  },
                  description: 'Fields to modify with their updates'
                },
                rename_module: {
                  type: 'string',
                  description: 'Custom name for this module'
                }
              },
              description: 'Customizations to apply to the template'
            },
            preview_only: {
              type: 'boolean',
              description: 'If true, just preview the customized template without installing'
            }
          },
          required: %w[template_key]
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      entity = @entity
      template_key = get_arg(args, :template_key)
      customizations = get_arg(args, :customizations) || {}
      preview_only = get_arg(args, :preview_only) || false
      
      # Validate required args
      if error = validate_required_args(args, [:template_key])
        return error
      end
      
      # Get the base template
      installer = Modules::TemplateInstaller.new(entity: entity, user: @user)
      base_template = installer.get_template_for_customization(template_key)
      
      unless base_template
        return { success: false, error: "Template '#{template_key}' not found" }
      end
      
      # Apply customizations
      customized = apply_customizations(base_template, customizations)
      
      if preview_only
        return {
          success: true,
          preview: true,
          template_name: customized[:name],
          fields: customized[:fields].map { |f| format_field(f) },
          message: "Here's what the customized template would look like. " \
                   "Say 'install it' or ask for more changes."
        }
      end
      
      # Install the customized template
      result = installer.install_customized(customized)
      
      if result[:success]
        {
          success: true,
          message: "Installed customized '#{customized[:name]}' module!",
          module_id: result[:module].id,
          fields_installed: customized[:fields].count
        }
      else
        { success: false, error: result[:error] }
      end
    end
    
    private
    
    def apply_customizations(template, customizations)
      result = template.deep_dup
      
      # Rename if requested
      if customizations['rename_module']
        result[:name] = customizations['rename_module']
      end
      
      # Remove fields
      if customizations['remove_fields']
        result[:fields].reject! { |f| customizations['remove_fields'].include?(f[:name].to_s) }
      end
      
      # Modify fields
      if customizations['modify_fields']
        customizations['modify_fields'].each do |mod|
          field = result[:fields].find { |f| f[:name].to_s == mod['name'] }
          field&.merge!(mod['updates'].symbolize_keys) if mod['updates']
        end
      end
      
      # Add fields
      if customizations['add_fields']
        customizations['add_fields'].each do |new_field|
          result[:fields] << new_field.symbolize_keys
        end
      end
      
      result
    end
    
    def format_field(field)
      base = "#{field[:name]} (#{field[:field_type]})"
      base += " - required" if field[:required]
      base += " - #{field[:description]}" if field[:description]
      base
    end
  end
end
