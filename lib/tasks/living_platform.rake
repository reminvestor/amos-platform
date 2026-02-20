# frozen_string_literal: true

namespace :living_platform do
  desc "Run complete Living Platform benchmark"
  task :benchmark, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id || Entity.first&.id
    raise "Usage: rake living_platform:benchmark[entity_id] or ensure at least one entity exists" unless entity_id

    entity = Entity.find(entity_id)
    puts "\n" + "="*70
    puts "🌱 LIVING PLATFORM BENCHMARK - #{entity.name}"
    puts "="*70

    benchmark = Benchmarks::LivingPlatformBenchmark.new(entity: entity)
    results = benchmark.run_full_benchmark

    puts "\n📊 RESULTS:"
    puts "  Overall Score:   #{results[:overall][:score]}%"
    puts "  Grade:           #{results[:overall][:grade]}"
    puts "  Passed:          #{results[:overall][:passed]}/#{results[:overall][:total]} tasks"
    puts "  Duration:        #{results[:duration_seconds]}s"
    puts "  Tokens Used:     #{results[:token_usage][:input] + results[:token_usage][:output]}"

    puts "\n📋 CATEGORY BREAKDOWN:"
    results[:categories].each do |category, data|
      puts "  #{category.to_s.titleize.ljust(20)} #{data[:score]}% (#{data[:passed]}/#{data[:total]})"
    end

    puts "\n" + "="*70 + "\n"
  end

  desc "Run quick Living Platform benchmark"
  task :quick_benchmark, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id || Entity.first&.id
    raise "Usage: rake living_platform:quick_benchmark[entity_id]" unless entity_id

    entity = Entity.find(entity_id)
    puts "\n🌱 Running quick Living Platform benchmark for #{entity.name}..."

    benchmark = Benchmarks::LivingPlatformBenchmark.new(entity: entity)
    results = benchmark.run_quick_benchmark

    puts "✅ Quick benchmark complete: #{results[:overall][:grade]} (#{results[:overall][:score]}%)"
  end

  desc "Show Living Platform status for an entity"
  task :status, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id || Entity.first&.id
    raise "Usage: rake living_platform:status[entity_id]" unless entity_id

    entity = Entity.find(entity_id)
    puts "\n" + "="*70
    puts "🌱 LIVING PLATFORM STATUS - #{entity.name}"
    puts "="*70

    # Latest perception
    perception = PlatformPerception.where(entity: entity).recent.first
    if perception
      puts "\n👁️ PERCEPTION (#{perception.perceived_at.strftime('%Y-%m-%d %H:%M')})"
      puts "  Health Score:      #{(perception.overall_health_score.to_f * 100).round}%"
      puts "  Active Agents:     #{perception.active_agents}"
      puts "  Success Rate 24h:  #{(perception.success_rate_24h.to_f * 100).round}%"
      puts "  Anomalies:         #{perception.anomaly_count} (#{perception.critical_anomalies} critical)"
    else
      puts "\n👁️ PERCEPTION: No data yet"
    end

    # Active goals
    goals = AgentGoal.where(entity: entity)
    puts "\n🎯 GOALS"
    puts "  Total:             #{goals.count}"
    puts "  Pending:           #{goals.pending.count}"
    puts "  In Progress:       #{goals.in_progress.count}"
    puts "  Completed:         #{goals.completed.count}"
    puts "  Failed:            #{goals.failed.count}"

    # Anomalies
    anomalies = PlatformAnomaly.where(entity: entity)
    puts "\n⚠️ ANOMALIES"
    puts "  Active:            #{anomalies.active.count}"
    puts "  Resolved:          #{anomalies.resolved.count}"
    puts "  Critical:          #{anomalies.active.where(severity: 'critical').count}"

    # Evolution cycles
    cycles = EvolutionCycle.where(entity: entity)
    puts "\n🧬 EVOLUTION"
    puts "  Total Cycles:      #{cycles.count}"
    puts "  Completed:         #{cycles.completed.count}"
    puts "  Total Promotions:  #{cycles.sum(:promotion_count)}"

    # Cost stats
    tracker = LivingPlatform::CostTracker.new(entity)
    cost = tracker.cost_breakdown(period: 7.days)
    puts "\n💰 COST (7 days)"
    puts "  Total AI Cost:     $#{cost[:total_cost]}"
    puts "  Living Platform:   $#{cost[:living_platform_cost]} (#{cost[:living_platform_percentage]}%)"

    puts "\n" + "="*70 + "\n"
  end

  desc "Run perception for an entity"
  task :perceive, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id || Entity.first&.id
    entity = Entity.find(entity_id)
    
    puts "👁️ Running perception for #{entity.name}..."
    
    service = LivingPlatform::PerceptionService.new(entity)
    perception = service.perceive(type: 'triggered')
    
    puts "✅ Perception complete:"
    puts "  Health Score: #{(perception.overall_health_score * 100).round}%"
    puts "  Anomalies: #{perception.anomaly_count}"
    puts "  Active Agents: #{perception.active_agents}"
  end

  desc "Run desire engine for an entity"
  task :desire, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id || Entity.first&.id
    entity = Entity.find(entity_id)
    
    puts "🎯 Running desire engine for #{entity.name}..."
    
    engine = LivingPlatform::DesireEngine.new(entity)
    result = engine.generate_daily_goals
    
    puts "✅ Goals generated: #{result[:goals_generated]}"
    puts "  Improvement: #{result[:breakdown][:improvement]}"
    puts "  Expansion: #{result[:breakdown][:expansion]}"
    puts "  Maintenance: #{result[:breakdown][:maintenance]}"
    puts "  Learning: #{result[:breakdown][:learning]}"
    puts "  Social: #{result[:breakdown][:social]}"
  end

  desc "Run evolution cycle for an entity"
  task :evolve, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id || Entity.first&.id
    entity = Entity.find(entity_id)
    
    puts "🧬 Running evolution cycle for #{entity.name}..."
    
    service = LivingPlatform::EvolutionCycleService.new(entity)
    cycle = service.run_cycle(type: 'triggered')
    
    puts "✅ Evolution cycle complete:"
    puts "  Status: #{cycle.status}"
    puts "  Goals Generated: #{cycle.goals_generated}"
    puts "  Experiments Started: #{cycle.experiments_started}"
    puts "  Promotions: #{cycle.promotion_count}"
    puts "  Duration: #{cycle.duration_minutes}m"
  end

  desc "Show cost analysis for Living Platform"
  task :costs, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id || Entity.first&.id
    entity = Entity.find(entity_id)
    
    puts "\n" + "="*70
    puts "💰 LIVING PLATFORM COST ANALYSIS - #{entity.name}"
    puts "="*70

    tracker = LivingPlatform::CostTracker.new(entity)
    
    # 7-day usage
    usage = tracker.get_usage(period: 7.days)
    puts "\n📊 USAGE (7 days)"
    puts "  Total Input Tokens:  #{usage[:total_input_tokens].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "  Total Output Tokens: #{usage[:total_output_tokens].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "  Total Cost:          $#{usage[:total_cost]}"
    puts "  Daily Average:       $#{usage[:daily_average]}"

    if usage[:by_source].any?
      puts "\n📋 BY SOURCE:"
      usage[:by_source].each do |source|
        puts "  #{source[:source].to_s.ljust(20)} $#{source[:cost].round(4)} (#{source[:input_tokens] + source[:output_tokens]} tokens)"
      end
    end

    # Breakdown
    breakdown = tracker.cost_breakdown(period: 7.days)
    puts "\n📈 BREAKDOWN"
    puts "  All AI Cost:         $#{breakdown[:total_cost]}"
    puts "  Living Platform:     $#{breakdown[:living_platform_cost]} (#{breakdown[:living_platform_percentage]}%)"
    puts "  Other:               $#{breakdown[:other_cost]}"

    # ROI
    roi = tracker.calculate_roi(period: 30.days)
    if roi
      puts "\n📊 ROI (30 days)"
      puts "  Cost:                $#{roi[:cost]}"
      puts "  Estimated Value:     $#{roi[:estimated_value]}"
      puts "  ROI:                 #{roi[:roi]}% #{roi[:roi_positive] ? '✅' : '⚠️'}"
    end

    # Alerts
    alerts = tracker.check_alerts
    if alerts.any?
      puts "\n⚠️ ALERTS:"
      alerts.each do |alert|
        puts "  #{alert[:type]}: #{alert[:message]}"
      end
    end

    puts "\n" + "="*70 + "\n"
  end

  desc "Test all Living Platform services"
  task :test_services, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id || Entity.first&.id
    entity = Entity.find(entity_id)
    
    puts "\n🧪 Testing Living Platform Services for #{entity.name}...\n"
    
    results = []
    
    # Test Perception
    print "  PerceptionService... "
    begin
      service = LivingPlatform::PerceptionService.new(entity)
      perception = service.perceive(type: 'triggered')
      puts "✅ (Health: #{(perception.overall_health_score * 100).round}%)"
      results << { service: 'Perception', status: 'pass' }
    rescue => e
      puts "❌ (#{e.message})"
      results << { service: 'Perception', status: 'fail', error: e.message }
    end
    
    # Test Desire Engine
    print "  DesireEngine... "
    begin
      engine = LivingPlatform::DesireEngine.new(entity)
      result = engine.generate_daily_goals
      puts "✅ (#{result[:goals_generated]} goals)"
      results << { service: 'DesireEngine', status: 'pass' }
    rescue => e
      puts "❌ (#{e.message})"
      results << { service: 'DesireEngine', status: 'fail', error: e.message }
    end
    
    # Test Evolution Cycle
    print "  EvolutionCycleService... "
    begin
      service = LivingPlatform::EvolutionCycleService.new(entity)
      cycle = service.run_cycle(type: 'triggered')
      puts "✅ (#{cycle.status})"
      results << { service: 'EvolutionCycle', status: 'pass' }
    rescue => e
      puts "❌ (#{e.message})"
      results << { service: 'EvolutionCycle', status: 'fail', error: e.message }
    end
    
    # Test Lifecycle Service
    print "  LifecycleService... "
    begin
      service = LivingPlatform::LifecycleService.new(entity)
      evaluations = service.evaluate_all_agents
      puts "✅ (#{evaluations.count} agents evaluated)"
      results << { service: 'Lifecycle', status: 'pass' }
    rescue => e
      puts "❌ (#{e.message})"
      results << { service: 'Lifecycle', status: 'fail', error: e.message }
    end
    
    # Test Cost Tracker
    print "  CostTracker... "
    begin
      tracker = LivingPlatform::CostTracker.new(entity)
      usage = tracker.get_usage(period: 1.day)
      puts "✅ ($#{usage[:total_cost]} today)"
      results << { service: 'CostTracker', status: 'pass' }
    rescue => e
      puts "❌ (#{e.message})"
      results << { service: 'CostTracker', status: 'fail', error: e.message }
    end
    
    # Summary
    passed = results.count { |r| r[:status] == 'pass' }
    puts "\n📊 Results: #{passed}/#{results.count} passed"
  end
end

