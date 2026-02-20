# frozen_string_literal: true

namespace :tools do
  desc "Diagnose tool definitions with invalid JSON schemas"
  task diagnose: :environment do
    puts "🔍 Scanning for tool definitions with invalid JSON schemas..."
    puts ""
    
    invalid_tools = []
    fixed_count = 0
    
    ToolDefinition.find_each do |tool|
      issues = []
      
      # Check for missing or invalid parameters
      if tool.parameters.blank?
        issues << "Missing parameters schema"
      elsif !tool.parameters.is_a?(Hash)
        issues << "Parameters is not a Hash"
      elsif !tool.parameters.key?('type')
        issues << "Missing 'type' field in parameters"
      else
        # Check properties
        properties = tool.parameters['properties']
        if properties.is_a?(Hash)
          properties.each do |prop_name, prop_def|
            next unless prop_def.is_a?(Hash)
            
            # Check for empty enum
            if prop_def.key?('enum')
              enum_val = prop_def['enum']
              if !enum_val.is_a?(Array) || enum_val.empty?
                issues << "Property '#{prop_name}' has invalid empty enum"
              end
            end
            
            # Check for missing type
            has_type = prop_def.key?('type')
            has_ref = prop_def.key?('$ref')
            has_composite = prop_def.key?('anyOf') || prop_def.key?('oneOf') || prop_def.key?('allOf')
            has_enum = prop_def.key?('enum') && prop_def['enum'].is_a?(Array) && prop_def['enum'].present?
            
            unless has_type || has_ref || has_composite || has_enum
              issues << "Property '#{prop_name}' is missing 'type' field"
            end
          end
        end
      end
      
      if issues.any?
        invalid_tools << { tool: tool, issues: issues }
      end
    end
    
    if invalid_tools.empty?
      puts "✅ All #{ToolDefinition.count} tool definitions have valid schemas!"
    else
      puts "❌ Found #{invalid_tools.length} tools with schema issues:\n\n"
      
      invalid_tools.each do |entry|
        tool = entry[:tool]
        puts "  📛 #{tool.name} (ID: #{tool.id})"
        puts "     Entity: #{tool.entity_id || 'global'}"
        puts "     Module: #{tool.app_module_id || 'none'}"
        puts "     Issues:"
        entry[:issues].each do |issue|
          puts "       - #{issue}"
        end
        puts ""
      end
    end
    
    puts "\n💡 Run 'rake tools:fix' to automatically repair these issues"
  end
  
  desc "Fix tool definitions with invalid JSON schemas"
  task fix: :environment do
    puts "🔧 Fixing tool definitions with invalid JSON schemas..."
    puts ""
    
    fixed_count = 0
    deleted_count = 0
    
    ToolDefinition.find_each do |tool|
      needs_fix = false
      needs_delete = false
      
      # Check for completely invalid parameters
      if tool.parameters.blank?
        # Set default schema
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
              puts "  🔧 Removed empty enum from #{tool.name}.#{prop_name}"
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
            puts "  🔧 Added missing type to #{tool.name}.#{prop_name}"
          end
        end
      end
      
      if needs_fix
        begin
          tool.save!(validate: false)  # Skip validation during repair
          fixed_count += 1
          puts "  ✅ Fixed #{tool.name}"
        rescue => e
          puts "  ❌ Failed to fix #{tool.name}: #{e.message}"
        end
      end
    end
    
    puts "\n✅ Fixed #{fixed_count} tool definitions"
    puts "   Deleted #{deleted_count} orphaned/unfixable tools" if deleted_count > 0
  end
  
  desc "List orphaned tools (associated with deleted modules or entities)"
  task orphans: :environment do
    puts "🔍 Scanning for orphaned tool definitions..."
    puts ""
    
    orphans = []
    
    ToolDefinition.find_each do |tool|
      is_orphan = false
      reason = nil
      
      # Check if entity exists
      if tool.entity_id.present? && !Entity.exists?(tool.entity_id)
        is_orphan = true
        reason = "Entity #{tool.entity_id} no longer exists"
      end
      
      # Check if app_module exists
      if tool.app_module_id.present? && !AppModule.exists?(tool.app_module_id)
        is_orphan = true
        reason = "AppModule #{tool.app_module_id} no longer exists"
      end
      
      if is_orphan
        orphans << { tool: tool, reason: reason }
      end
    end
    
    if orphans.empty?
      puts "✅ No orphaned tool definitions found!"
    else
      puts "⚠️  Found #{orphans.length} orphaned tools:\n\n"
      
      orphans.each do |entry|
        tool = entry[:tool]
        puts "  📛 #{tool.name} (ID: #{tool.id})"
        puts "     Reason: #{entry[:reason]}"
        puts ""
      end
      
      puts "\n💡 Run 'rake tools:delete_orphans' to remove these"
    end
  end
  
  desc "Delete orphaned tool definitions"
  task delete_orphans: :environment do
    puts "🗑️  Deleting orphaned tool definitions..."
    
    deleted_count = 0
    
    ToolDefinition.find_each do |tool|
      is_orphan = false
      
      # Check if entity exists
      if tool.entity_id.present? && !Entity.exists?(tool.entity_id)
        is_orphan = true
      end
      
      # Check if app_module exists
      if tool.app_module_id.present? && !AppModule.exists?(tool.app_module_id)
        is_orphan = true
      end
      
      if is_orphan
        puts "  🗑️  Deleting #{tool.name} (ID: #{tool.id})"
        tool.destroy
        deleted_count += 1
      end
    end
    
    puts "\n✅ Deleted #{deleted_count} orphaned tools"
  end
  
  desc "Full cleanup: diagnose, fix, and remove orphans"
  task cleanup: [:diagnose, :fix, :delete_orphans] do
    puts "\n✅ Tool cleanup complete!"
  end

  desc "Preview redundant module CRUD tools that would be deleted (dry run)"
  task preview_module_crud: :environment do
    puts "🔍 Scanning for auto-generated module CRUD ToolDefinitions..."
    puts "   These are redundant -- platform tools handle all module CRUD natively.\n\n"

    crud_tools = ToolDefinition.where.not(app_module_id: nil)
    total = crud_tools.count

    if total == 0
      puts "✅ No module CRUD tools found. Nothing to clean up!"
      next
    end

    by_entity = crud_tools.includes(:entity, :app_module).group_by(&:entity_id)

    by_entity.each do |entity_id, tools|
      entity_name = tools.first.entity&.name || "Unknown"
      puts "  📦 Entity: #{entity_name} (ID: #{entity_id}) — #{tools.size} CRUD tools"

      tools.group_by { |t| t.app_module&.name || "Deleted module" }.each do |mod_name, mod_tools|
        puts "     └─ Module: #{mod_name}"
        mod_tools.each do |tool|
          puts "        • #{tool.name} (ID: #{tool.id}, created: #{tool.created_at&.strftime('%Y-%m-%d %H:%M')})"
        end
      end
      puts ""
    end

    puts "="*60
    puts "📊 Total: #{total} redundant module CRUD tools across #{by_entity.size} entities"
    puts "💡 Run 'rake tools:delete_module_crud' to remove them"
    puts "   Or 'rake tools:delete_module_crud_for_entity[ENTITY_ID]' for a specific entity"
  end

  desc "Delete all auto-generated module CRUD tools (they duplicate platform tools)"
  task delete_module_crud: :environment do
    crud_tools = ToolDefinition.where.not(app_module_id: nil)
    total = crud_tools.count

    if total == 0
      puts "✅ No module CRUD tools found. Nothing to clean up!"
      next
    end

    puts "🗑️  Deleting #{total} redundant module CRUD ToolDefinitions..."

    deleted = 0
    crud_tools.find_each do |tool|
      entity_name = tool.entity&.name || "?"
      puts "  🗑️  #{tool.name} (entity: #{entity_name}, module: #{tool.app_module&.name || 'deleted'})"
      tool.destroy
      deleted += 1
    end

    # Clear the ToolCatalog cache so stale tools aren't served
    if defined?(Tools::ToolCatalog)
      Tools::ToolCatalog.instance.instance_variable_set(:@entity_tools, {})
      puts "\n🔄 ToolCatalog cache cleared"
    end

    puts "\n✅ Deleted #{deleted} redundant module CRUD tools"
    puts "   Platform tools (platform_create/query/update/execute) handle all module CRUD."
  end

  desc "Delete module CRUD tools for a specific entity"
  task :delete_module_crud_for_entity, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id
    raise "Usage: rake tools:delete_module_crud_for_entity[ENTITY_ID]" unless entity_id

    entity = Entity.find(entity_id)
    crud_tools = ToolDefinition.where(entity_id: entity.id).where.not(app_module_id: nil)
    total = crud_tools.count

    if total == 0
      puts "✅ No module CRUD tools found for #{entity.name}. Nothing to clean up!"
      next
    end

    puts "🗑️  Deleting #{total} redundant module CRUD tools for #{entity.name}..."

    deleted = 0
    crud_tools.find_each do |tool|
      puts "  🗑️  #{tool.name} (module: #{tool.app_module&.name || 'deleted'})"
      tool.destroy
      deleted += 1
    end

    # Clear the ToolCatalog cache for this entity
    if defined?(Tools::ToolCatalog)
      Tools::ToolCatalog.instance.instance_variable_set(:@entity_tools, {})
      puts "\n🔄 ToolCatalog cache cleared"
    end

    puts "\n✅ Deleted #{deleted} redundant module CRUD tools for #{entity.name}"
  end
end

