# frozen_string_literal: true

namespace :app_build do
  desc "Preview stuck modules (generating with tables) and stale plans"
  task preview: :environment do
    puts "🔍 Scanning for stuck app builds...\n\n"

    stuck_modules = AppModule.where(status: "generating")
    recoverable = 0
    unrecoverable = 0

    stuck_modules.find_each do |m|
      has_table = ActiveRecord::Base.connection.table_exists?(m.slug.pluralize) rescue false
      has_code = m.module_codes.where(code_type: "model").exists?
      entity = m.entity

      status = if has_table && has_code
        recoverable += 1
        "✅ recoverable"
      else
        unrecoverable += 1
        "⚠️  missing #{has_table ? '' : 'table '}#{has_code ? '' : 'code'}"
      end

      puts "  #{status} — #{m.name} (id=#{m.id}, entity: #{entity&.name || m.entity_id}, slug: #{m.slug})"
    end

    puts "\n📊 Summary: #{stuck_modules.count} stuck modules (#{recoverable} recoverable, #{unrecoverable} need attention)\n\n"

    stale_plans = ApplicationPlan.where(status: %w[paused building]).where("updated_at < ?", 1.hour.ago)
    puts "📋 Stale plans (paused/building for >1 hour): #{stale_plans.count}"
    stale_plans.find_each do |p|
      entity = Entity.find_by(id: p.entity_id)
      completed = p.build_results&.dig("completed_phases") || []
      puts "  #{p.name} (id=#{p.id}, status: #{p.status}, entity: #{entity&.name || p.entity_id})"
      puts "    completed phases: #{completed.any? ? completed.join(', ') : 'none'}"
      puts "    error: #{p.error_message.to_s.truncate(120)}" if p.error_message.present?
    end

    failed_plans = ApplicationPlan.where(status: "failed").where("updated_at > ?", 30.days.ago)
    puts "\n❌ Recently failed plans (last 30 days): #{failed_plans.count}"
    failed_plans.find_each do |p|
      entity = Entity.find_by(id: p.entity_id)
      puts "  #{p.name} (id=#{p.id}, entity: #{entity&.name || p.entity_id})"
      puts "    error: #{p.error_message.to_s.truncate(120)}"
    end

    dupes = AppModule.group(:entity_id, :name).having("COUNT(*) > 1").count
    if dupes.any?
      puts "\n🔄 Duplicate module names (same entity + name):"
      dupes.each do |(entity_id, name), count|
        entity = Entity.find_by(id: entity_id)
        puts "  #{entity&.name || entity_id}: '#{name}' x#{count}"
      end
    end

    puts "\nRun `rails app_build:recover` to activate recoverable modules and resolve stale plans."
  end

  desc "Recover stuck modules and stale plans"
  task recover: :environment do
    puts "🔧 Recovering stuck app builds...\n\n"

    activated = 0
    skipped = 0

    AppModule.where(status: "generating").find_each do |m|
      has_table = ActiveRecord::Base.connection.table_exists?(m.slug.pluralize) rescue false
      has_code = m.module_codes.where(code_type: "model").exists?

      if has_table && has_code
        m.activate!
        activated += 1
        puts "  ✅ Activated: #{m.name} (id=#{m.id}, entity_id=#{m.entity_id})"
      else
        skipped += 1
        puts "  ⏭️  Skipped: #{m.name} (id=#{m.id}) — missing #{has_table ? '' : 'table '}#{has_code ? '' : 'code'}"
      end
    end

    puts "\n📊 Modules: #{activated} activated, #{skipped} skipped\n\n"

    resolved_plans = 0
    ApplicationPlan.where(status: %w[paused building]).where("updated_at < ?", 1.hour.ago).find_each do |p|
      completed = p.build_results&.dig("completed_phases") || []
      active_modules = AppModule.where(entity_id: p.entity_id, status: "active").count

      if completed.include?("modules") && active_modules > 0
        p.update!(status: "completed", error_message: nil)
        puts "  ✅ Completed stale plan: #{p.name} (id=#{p.id}) — #{active_modules} active modules in entity"
      else
        p.update!(status: "failed", error_message: "Auto-failed: stale #{p.status} plan with no progress")
        puts "  ❌ Failed stale plan: #{p.name} (id=#{p.id}) — no active modules"
      end
      resolved_plans += 1
    end

    puts "\n📊 Plans: #{resolved_plans} resolved"
    puts "\n✅ Recovery complete. Run `rails app_build:preview` to verify."
  end

  desc "Recover stuck modules for a specific entity"
  task :recover_entity, [:entity_id] => :environment do |_t, args|
    entity_id = args[:entity_id].to_i
    entity = Entity.find(entity_id)
    puts "🔧 Recovering stuck builds for #{entity.name} (id=#{entity_id})...\n\n"

    activated = 0
    AppModule.where(entity_id: entity_id, status: "generating").find_each do |m|
      has_table = ActiveRecord::Base.connection.table_exists?(m.slug.pluralize) rescue false
      has_code = m.module_codes.where(code_type: "model").exists?

      if has_table && has_code
        m.activate!
        activated += 1
        puts "  ✅ Activated: #{m.name} (slug=#{m.slug})"
      else
        puts "  ⏭️  Skipped: #{m.name} — missing #{has_table ? '' : 'table '}#{has_code ? '' : 'code'}"
      end
    end

    ApplicationPlan.where(entity_id: entity_id, status: %w[paused building failed]).find_each do |p|
      active_modules = AppModule.where(entity_id: entity_id, status: "active").count
      if active_modules > 0 && p.status != "failed"
        p.update!(status: "completed", error_message: nil)
        puts "  ✅ Completed plan: #{p.name} (id=#{p.id})"
      elsif p.status != "failed"
        p.update!(status: "failed", error_message: "Recovered: no active modules")
        puts "  ❌ Failed plan: #{p.name} (id=#{p.id}) — no active modules"
      else
        puts "  ⏭️  Already failed: #{p.name} (id=#{p.id})"
      end
    end

    puts "\n✅ Recovered #{activated} modules for #{entity.name}"
  end
end
