# frozen_string_literal: true

namespace :modules do
  desc "Delete all custom apps and modules for an entity (or all entities)"
  task :cleanup, [:entity_id] => :environment do |t, args|
    if args[:entity_id].present?
      entities = Entity.where(id: args[:entity_id])
    else
      entities = Entity.all
    end

    entities.each do |entity|
      puts "\n🧹 Cleaning up modules for Entity: #{entity.name} (ID: #{entity.id})"
      
      # Count before
      apps_count = entity.apps.count
      modules_count = entity.app_modules.count
      
      puts "  Found: #{apps_count} apps, #{modules_count} modules"
      
      # Get all module IDs first
      module_ids = entity.app_modules.pluck(:id)
      app_ids = entity.apps.pluck(:id)
      
      # Delete all related records using raw SQL to avoid FK issues
      # This is more reliable than trying to guess all the associations
      
      tables_with_app_module_id = %w[
        module_canvases
        module_codes
        module_actions
        module_design_sessions
        module_builder_sessions
        tool_definitions
        dynamic_tools
        module_webhooks
        module_integrations
      ]
      
      tables_with_app_module_id.each do |table|
        if ActiveRecord::Base.connection.table_exists?(table)
          if ActiveRecord::Base.connection.column_exists?(table, :app_module_id)
            count = ActiveRecord::Base.connection.execute(
              "DELETE FROM #{table} WHERE app_module_id IN (#{module_ids.join(',') || 0}) RETURNING id"
            ).count rescue 0
            puts "  ✓ Deleted #{count} from #{table}" if count > 0
          end
        end
      end
      
      # Also check for entity_id references
      tables_with_entity_id = %w[
        module_design_sessions
        module_builder_sessions
      ]
      
      tables_with_entity_id.each do |table|
        if ActiveRecord::Base.connection.table_exists?(table)
          if ActiveRecord::Base.connection.column_exists?(table, :entity_id)
            count = ActiveRecord::Base.connection.execute(
              "DELETE FROM #{table} WHERE entity_id = #{entity.id} RETURNING id"
            ).count rescue 0
            puts "  ✓ Deleted #{count} from #{table} (by entity)" if count > 0
          end
        end
      end
      
      # Now delete app_modules
      if module_ids.any?
        count = ActiveRecord::Base.connection.execute(
          "DELETE FROM app_modules WHERE id IN (#{module_ids.join(',')}) RETURNING id"
        ).count rescue 0
        puts "  ✓ Deleted #{count} app modules"
      end
      
      # Delete apps
      if app_ids.any?
        count = ActiveRecord::Base.connection.execute(
          "DELETE FROM apps WHERE id IN (#{app_ids.join(',')}) RETURNING id"
        ).count rescue 0
        puts "  ✓ Deleted #{count} apps"
      end
      
      puts "  ✅ Cleanup complete for #{entity.name}"
    end
    
    puts "\n✅ All module cleanup complete!"
  end

  desc "List all custom apps and modules"
  task list: :environment do
    Entity.all.each do |entity|
      apps = entity.apps
      modules = entity.app_modules
      
      next if apps.empty? && modules.empty?
      
      puts "\n📦 Entity: #{entity.name} (ID: #{entity.id})"
      
      if apps.any?
        puts "  Apps (#{apps.count}):"
        apps.each do |app|
          puts "    - #{app.name} (#{app.slug}) [#{app.status}]"
        end
      end
      
      if modules.any?
        puts "  Modules (#{modules.count}):"
        modules.each do |mod|
          fields_count = mod.enhanced_fields&.count || 0
          canvases_count = mod.module_canvases.count
          puts "    - #{mod.name} (#{mod.slug}) [#{mod.status}] - #{fields_count} fields, #{canvases_count} canvases"
        end
      end
    end
  end

  desc "Drop dynamic module tables (DANGEROUS - use with caution)"
  task drop_tables: :environment do
    puts "⚠️  This will drop all dynamic module tables!"
    puts "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
    sleep 5
    
    # Find all module table names
    Entity.all.each do |entity|
      entity.app_modules.each do |mod|
        table_name = mod.slug.pluralize
        
        if ActiveRecord::Base.connection.table_exists?(table_name)
          puts "  Dropping table: #{table_name}"
          ActiveRecord::Base.connection.drop_table(table_name)
        end
      end
    end
    
    puts "✅ Dynamic tables dropped"
  end
  
  desc "Force delete all modules using CASCADE (NUCLEAR OPTION)"
  task :force_cleanup, [:entity_id] => :environment do |t, args|
    puts "⚠️  NUCLEAR OPTION: This will forcefully delete all modules!"
    puts "Press Ctrl+C to cancel, or wait 3 seconds to continue..."
    sleep 3
    
    if args[:entity_id].present?
      entity_ids = [args[:entity_id]]
    else
      entity_ids = Entity.pluck(:id)
    end
    
    entity_ids.each do |entity_id|
      entity = Entity.find(entity_id)
      puts "\n🔥 Force cleaning Entity: #{entity.name} (ID: #{entity_id})"
      
      module_ids = AppModule.where(entity_id: entity_id).pluck(:id)
      app_ids = App.where(entity_id: entity_id).pluck(:id)
      
      next if module_ids.empty? && app_ids.empty?
      
      # Disable foreign key checks temporarily
      ActiveRecord::Base.connection.execute("SET session_replication_role = 'replica';")
      
      begin
        if module_ids.any?
          # Delete from all related tables
          %w[
            module_canvases module_codes module_actions module_design_sessions 
            module_builder_sessions tool_definitions dynamic_tools
          ].each do |table|
            if ActiveRecord::Base.connection.table_exists?(table) && 
               ActiveRecord::Base.connection.column_exists?(table, :app_module_id)
              ActiveRecord::Base.connection.execute(
                "DELETE FROM #{table} WHERE app_module_id IN (#{module_ids.join(',')})"
              )
            end
          end
          
          # Delete app_modules
          ActiveRecord::Base.connection.execute(
            "DELETE FROM app_modules WHERE id IN (#{module_ids.join(',')})"
          )
          puts "  ✓ Deleted #{module_ids.count} app modules"
        end
        
        if app_ids.any?
          ActiveRecord::Base.connection.execute(
            "DELETE FROM apps WHERE id IN (#{app_ids.join(',')})"
          )
          puts "  ✓ Deleted #{app_ids.count} apps"
        end
      ensure
        # Re-enable foreign key checks
        ActiveRecord::Base.connection.execute("SET session_replication_role = 'origin';")
      end
      
      puts "  ✅ Force cleanup complete for #{entity.name}"
    end
    
    puts "\n✅ Force cleanup complete!"
  end
end
