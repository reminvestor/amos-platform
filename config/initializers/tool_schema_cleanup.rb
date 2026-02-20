# frozen_string_literal: true

# Cleanup invalid tool schemas on server boot
# This fixes the recurring JSON Schema 2020-12 validation errors from Bedrock

Rails.application.config.after_initialize do
  next if ENV["SECRET_KEY_BASE_DUMMY"].present? # Container build asset precompilation
  begin
    next unless defined?(ToolDefinition) && ActiveRecord::Base.connection.table_exists?('tool_definitions')
  rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad
    next
  end
  
  # Run synchronously to ensure cleanup happens before any requests
  Rails.logger.info "[ToolSchemaCleanup] Starting automatic tool schema cleanup..."
  
  fixed_count = 0
  
  begin
    ToolDefinition.find_each do |tool|
      needs_fix = false
      
      # Check for completely invalid parameters
      if tool.parameters.blank?
        tool.parameters = { 'type' => 'object', 'properties' => {}, 'required' => [] }
        needs_fix = true
      elsif !tool.parameters.is_a?(Hash)
        tool.parameters = { 'type' => 'object', 'properties' => {}, 'required' => [] }
        needs_fix = true
      elsif !tool.parameters.key?('type')
        tool.parameters['type'] = 'object'
        needs_fix = true
      end
      
      # Fix properties
      if tool.parameters.is_a?(Hash) && tool.parameters['properties'].is_a?(Hash)
        tool.parameters['properties'].each do |prop_name, prop_def|
          next unless prop_def.is_a?(Hash)
          
          # Fix empty enum
          if prop_def.key?('enum')
            enum_val = prop_def['enum']
            if !enum_val.is_a?(Array) || enum_val.empty?
              prop_def.delete('enum')
              needs_fix = true
            end
          end
          
          # Fix missing type
          has_type = prop_def.key?('type')
          has_ref = prop_def.key?('$ref')
          has_composite = prop_def.key?('anyOf') || prop_def.key?('oneOf') || prop_def.key?('allOf')
          has_enum = prop_def.key?('enum') && prop_def['enum'].is_a?(Array) && prop_def['enum'].present?
          
          unless has_type || has_ref || has_composite || has_enum
            prop_def['type'] = 'string'
            needs_fix = true
          end
        end
      end
      
      if needs_fix
        begin
          tool.save!(validate: false)
          fixed_count += 1
        rescue => e
          Rails.logger.warn "[ToolSchemaCleanup] Failed to fix #{tool.name}: #{e.message}"
        end
      end
    end
    
    if fixed_count > 0
      Rails.logger.info "[ToolSchemaCleanup] ✅ Fixed #{fixed_count} tool schemas"
    else
      Rails.logger.debug "[ToolSchemaCleanup] All tool schemas are valid"
    end
  rescue => e
    Rails.logger.error "[ToolSchemaCleanup] Error during cleanup: #{e.message}"
  end
rescue => e
  Rails.logger.warn "[ToolSchemaCleanup] Skipped: #{e.message}"
end
