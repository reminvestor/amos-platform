# frozen_string_literal: true

# ============================================
# BUSINESS OPERATIONS BENCHMARK (BOB) v1.0
# "MMLU for Running a Business"
# 
# 100 tasks across 10 categories testing Scout
# as a fractional COO / Chief of Staff
# ============================================

namespace :benchmark do
  namespace :business do
    desc "Show Business Benchmark info"
    task :info => :environment do
      puts "\n" + "=" * 70
      puts "🏢 BUSINESS OPERATIONS BENCHMARK (BOB) v1.0"
      puts "=" * 70
      puts ""
      puts "100 tasks across 10 categories testing Scout as a fractional COO"
      puts ""
      puts "Categories:"
      Benchmarks::BusinessBenchmark::CATEGORIES.each do |key, name|
        count = Benchmarks::BusinessBenchmark.tasks_by_category(key).size
        puts "  #{name}: #{count} tasks"
      end
      puts ""
      puts "Difficulty breakdown:"
      [:easy, :medium, :hard].each do |diff|
        count = Benchmarks::BusinessBenchmark.by_difficulty(diff).size
        puts "  #{diff.to_s.capitalize}: #{count} tasks"
      end
      puts ""
      puts "Commands:"
      puts "  rake benchmark:business:quick     # Run 2 tasks per category (20 total)"
      puts "  rake benchmark:business:full      # Run all 100 tasks"
      puts "  rake benchmark:business:compare   # Compare Raw Claude vs AMOS"
      puts "  rake benchmark:business:single[task_id]  # Run single task"
      puts "  rake benchmark:business:category[category]  # Run one category"
      puts "=" * 70
    end

    desc "Run quick Business Benchmark (2 per category = 20 tasks)"
    task :quick => :environment do
      # Use isolated test environment with cleanup
      runner = Benchmarks::BusinessBenchmarkRunner.new(use_test_env: true, cleanup_before: true)
      puts "Using test environment: #{runner.entity.name}"
      runner.run_quick_benchmark(tasks_per_category: 2)
    end

    desc "Run full Business Benchmark (all tasks)"
    task :full => :environment do
      # Use isolated test environment with cleanup
      runner = Benchmarks::BusinessBenchmarkRunner.new(use_test_env: true, cleanup_before: true)
      puts "Using test environment: #{runner.entity.name}"
      runner.run_full_benchmark
    end

    desc "Compare Raw Claude vs AMOS on Business Benchmark"
    task :compare, [:tasks_per_category] => :environment do |t, args|
      tasks_per_category = (args[:tasks_per_category] || 1).to_i
      
      # Use isolated test environment with cleanup
      runner = Benchmarks::BusinessBenchmarkRunner.new(use_test_env: true, cleanup_before: true)
      puts "Using test environment: #{runner.entity.name}"
      runner.run_comparison(tasks_per_category: tasks_per_category)
    end

    desc "Run benchmark on real entity (no isolation)"
    task :real, [:tasks_per_category] => :environment do |t, args|
      tasks_per_category = (args[:tasks_per_category] || 2).to_i
      entity = Entity.first
      user = User.first
      
      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      puts "⚠️  Running on REAL entity: #{entity.name}"
      puts "   This will create real data. Use benchmark:business:quick for isolated testing."
      
      runner = Benchmarks::BusinessBenchmarkRunner.new(entity: entity, user: user)
      runner.run_quick_benchmark(tasks_per_category: tasks_per_category)
    end

    desc "Clean up test environment data"
    task :cleanup => :environment do
      puts "Cleaning up benchmark test environment..."
      stats = Benchmarks::TestEnvironment.cleanup!
      puts "Removed: #{stats.map { |k, v| "#{v} #{k}" }.join(', ')}"
    end

    desc "Show test environment status"
    task :status => :environment do
      status = Benchmarks::TestEnvironment.status
      puts "\nBenchmark Test Environment Status:"
      puts "  Entity: #{status[:entity_name]} (ID: #{status[:entity_id]})"
      puts "  User: #{status[:user_email]} (ID: #{status[:user_id]})"
      puts "  Data counts:"
      status[:data_counts].each do |type, count|
        puts "    #{type}: #{count}"
      end
    end

    desc "Run a single Business Benchmark task"
    task :single, [:task_id] => :environment do |t, args|
      task_id = args[:task_id]
      
      unless task_id
        puts "Usage: rake benchmark:business:single[task_id]"
        puts "Example: rake benchmark:business:single[strategy_001]"
        next
      end

      task = Benchmarks::BusinessBenchmark.task(task_id)
      unless task
        puts "❌ Task '#{task_id}' not found"
        puts "Available task IDs start with: strategy_, finance_, sales_, marketing_, operations_, hr_, support_, analytics_, admin_, compliance_, grounded_, creation_, evolution_"
        next
      end

      # Use isolated test environment
      runner = Benchmarks::BusinessBenchmarkRunner.new(use_test_env: true, cleanup_before: false)

      puts "\n" + "=" * 70
      puts "🏢 Running: #{task[:name]}"
      puts "=" * 70
      puts ""
      puts "Test Environment: #{runner.entity.name}"
      puts "Category: #{Benchmarks::BusinessBenchmark::CATEGORIES[task[:category]] || task[:category]}"
      puts "Difficulty: #{task[:difficulty]}"
      puts ""
      puts "Scenario:"
      puts task[:scenario]
      puts ""
      puts "Request:"
      puts task[:request]
      puts ""
      puts "Rubric (what a good answer should include):"
      task[:rubric].each { |r| puts "  • #{r}" }
      puts ""
      puts "-" * 70
      puts "Running with AMOS (Scout)..."
      puts "-" * 70

      result = runner.run_task(task, use_scout: true, verify_assets: true)

      puts ""
      puts "Response:"
      puts result[:response]
      puts ""
      puts "-" * 70
      puts "⏱️  Time: #{result[:elapsed_ms]}ms"
      puts "✅ Success: #{result[:success]}"
      puts ""
      puts "🔧 Grounding Metrics:"
      puts "   Tool calls: #{result[:tool_calls] || 0}"
      puts "   Agent calls: #{result[:agent_calls] || 0}"
      if result[:tools_used]&.any?
        puts "   Tools used: #{result[:tools_used].join(', ')}"
      end
      if result[:agents_used]&.any?
        puts "   Agents used: #{result[:agents_used].join(', ')}"
      end
      if result[:data_sources]&.any?
        puts "   Data sources: #{result[:data_sources].map { |ds| ds[:type] }.uniq.join(', ')}"
      end
      puts ""
      if result[:grounded]
        puts "   ✅ GROUNDED: Response used external data sources"
      else
        puts "   ⚠️  UNGROUNDED: Pure LLM response - verify for hallucinations"
      end
      puts "=" * 70
    end

    desc "Run category-specific benchmark"
    task :category, [:category] => :environment do |t, args|
      category = args[:category]&.to_sym
      
      unless category && Benchmarks::BusinessBenchmark::CATEGORIES.key?(category)
        puts "Usage: rake benchmark:business:category[category]"
        puts "Available categories:"
        Benchmarks::BusinessBenchmark::CATEGORIES.each do |key, name|
          puts "  #{key} - #{name}"
        end
        next
      end

      entity = Entity.first
      user = User.first

      tasks = Benchmarks::BusinessBenchmark.tasks_by_category(category)
      
      puts "\n" + "=" * 70
      puts "🏢 #{Benchmarks::BusinessBenchmark::CATEGORIES[category]}"
      puts "=" * 70
      puts "Running #{tasks.size} tasks..."
      puts ""

      runner = Benchmarks::BusinessBenchmarkRunner.new(entity: entity, user: user)
      
      tasks.each_with_index do |task, idx|
        print "  #{idx + 1}/#{tasks.size}: #{task[:name].truncate(40)}... "
        result = runner.run_task(task, use_scout: true)
        runner.results << result
        puts result[:success] ? "✓ (#{result[:elapsed_ms]}ms)" : "✗"
        sleep(0.3)
      end

      puts ""
      runner.generate_report
    end

    desc "List all task IDs"
    task :list => :environment do
      puts "\n" + "=" * 70
      puts "📋 ALL BUSINESS BENCHMARK TASKS"
      puts "=" * 70
      puts ""
      
      Benchmarks::BusinessBenchmark::CATEGORIES.each do |category_key, category_name|
        puts "#{category_name}:"
        Benchmarks::BusinessBenchmark.tasks_by_category(category_key).each do |task|
          grounded = task[:grounding_required] ? '🔧' : '📝'
          puts "  #{grounded} #{task[:id].ljust(20)} - #{task[:name]} [#{task[:difficulty]}]"
        end
        puts ""
      end
      
      puts "Legend: 🔧 = Requires tools/data, 📝 = Pure reasoning"
    end

    desc "Show Scout's tool and agent access"
    task :scout_access => :environment do
      entity = Entity.first
      
      puts "\n" + "=" * 70
      puts "🔧 SCOUT CAPABILITY CHECK"
      puts "=" * 70
      puts ""

      # Get Scout's loadout configuration
      config = ScoutLoadoutConfiguration.for_entity(entity)
      
      puts "Configuration:"
      puts "  Tiered Discovery: #{config.use_tiered_discovery ? '✅ Enabled' : '❌ Disabled'}"
      puts "  Max Discovered Tools: #{config.max_discovered_tools}"
      puts ""

      puts "Allowed Tools (#{config.effective_tool_allowlist.size}):"
      config.effective_tool_allowlist.each do |tool|
        puts "  ✅ #{tool}"
      end
      puts ""

      # Check key tools for grounded tasks
      puts "Key Tools for Grounded Tasks:"
      key_tools = {
        'web_search' => 'Web research, current events, competitor info',
        'get_data' => 'Query CRM, contacts, campaigns, pipeline',
        'delegate_to_agent' => 'Delegate to specialist agents',
        'invoke_agent_plugin' => 'Run specific agents',
        'ask_agent_for_help' => 'Collaboration with other agents',
        'list_available_agents' => 'See available specialists',
        'list_connections' => 'Check connected integrations',
        'list_operations' => 'See available API operations',
        'read_document' => 'Access uploaded documents',
        'query_document_content' => 'Search document contents'
      }
      
      key_tools.each do |tool, description|
        has_it = config.tool_allowed?(tool)
        puts "  #{has_it ? '✅' : '❌'} #{tool.ljust(25)} - #{description}"
      end
      puts ""

      # List available agents
      puts "Available Specialist Agents:"
      agents = AgentPlugin.where(entity: [entity, nil]).where(status: 'active')
      if agents.empty?
        agents = AgentPlugin.where(entity: [entity, nil]).limit(15)
      end
      
      agents.each do |agent|
        puts "  🤖 #{agent.slug.ljust(30)} - #{agent.name}"
      end
      puts ""

      puts "=" * 70
      puts "To enable tiered discovery (RAG-based tool finding):"
      puts "  Go to AI Settings > Scout > Enable Dynamic Tool Discovery"
      puts "=" * 70
    end

    desc "Run grounded tasks only (tests tool usage)"
    task :grounded => :environment do
      entity = Entity.first
      user = User.first
      
      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      tasks = Benchmarks::BusinessBenchmark.tasks_by_category(:grounded)
      
      puts "\n" + "=" * 70
      puts "🔧 GROUNDED TASKS BENCHMARK"
      puts "=" * 70
      puts "Testing #{tasks.size} tasks that REQUIRE tool usage"
      puts "These tasks cannot be answered correctly without external data"
      puts "=" * 70
      puts ""

      runner = Benchmarks::BusinessBenchmarkRunner.new(entity: entity, user: user)
      
      tasks.each_with_index do |task, idx|
        print "  #{idx + 1}/#{tasks.size}: #{task[:name].truncate(35)}... "
        result = runner.run_task(task, use_scout: true)
        runner.results << result
        
        if result[:grounded]
          puts "✅ GROUNDED (#{result[:tools_used].join(', ')})"
        else
          puts "⚠️  UNGROUNDED"
        end
        sleep(0.5)
      end

      puts ""
      runner.generate_report
    end

    # ============================================
    # V2 BENCHMARK - HARD MODE
    # ============================================
    namespace :v2 do
      desc "Show V2 Benchmark info (Hard Mode)"
      task :info => :environment do
        summary = Benchmarks::BusinessBenchmarkV2.summary
        
        puts "\n" + "=" * 70
        puts "🔥 BUSINESS OPERATIONS BENCHMARK (BOB) v2.0 - HARD MODE"
        puts "=" * 70
        puts ""
        puts "Total tasks: #{summary[:total]}"
        puts ""
        puts "Categories:"
        Benchmarks::BusinessBenchmarkV2::CATEGORIES.each do |key, name|
          count = Benchmarks::BusinessBenchmarkV2.tasks_by_category(key).size
          puts "  #{name}: #{count} tasks"
        end
        puts ""
        puts "Difficulty breakdown:"
        summary[:by_difficulty].each do |diff, count|
          puts "  #{diff.to_s.capitalize}: #{count} tasks"
        end
        puts ""
        puts "Special categories:"
        puts "  Grounded (require tools): #{summary[:grounded]}"
        puts "  Creation (make assets): #{summary[:creation]}"
        puts "  Delegation (use agents): #{summary[:delegation]}"
        puts "  Multi-agent: #{summary[:multi_agent]}"
        puts "  Extreme challenges: #{summary[:extreme]}"
        puts ""
        puts "Commands:"
        puts "  rake benchmark:business:v2:quick    # Run 1 task per category"
        puts "  rake benchmark:business:v2:full     # Run all tasks"
        puts "  rake benchmark:business:v2:extreme  # Run only extreme challenges"
        puts "  rake benchmark:business:v2:single[task_id]  # Run single task"
        puts "=" * 70
      end

      desc "Run V2 quick benchmark (1 per category)"
      task :quick => :environment do
        runner = Benchmarks::BusinessBenchmarkRunner.new(use_test_env: true, cleanup_before: true)
        puts "Using test environment: #{runner.entity.name}"
        
        puts "\n" + "=" * 70
        puts "🔥 BOB v2.0 - QUICK BENCHMARK"
        puts "=" * 70
        puts ""

        Benchmarks::BusinessBenchmarkV2::CATEGORIES.each do |category_key, category_name|
          tasks = Benchmarks::BusinessBenchmarkV2.tasks_by_category(category_key).first(1)
          next if tasks.empty?
          
          puts "📁 #{category_name}"
          tasks.each do |task|
            print "  • #{task[:name].truncate(50)}... "
            result = runner.run_task(task, use_scout: true)
            runner.results << result
            
            status = result[:success] ? "✓" : "✗"
            tools = result[:tools_used]&.any? ? " 🔧#{result[:tools_used].size}" : ""
            agents = result[:agents_used]&.any? ? " 🤖#{result[:agents_used].size}" : ""
            puts "#{status}#{tools}#{agents}"
            sleep(0.3)
          end
        end
        puts ""
        runner.generate_report
      end

      desc "Run V2 full benchmark (all tasks)"
      task :full => :environment do
        runner = Benchmarks::BusinessBenchmarkRunner.new(use_test_env: true, cleanup_before: true)
        puts "Using test environment: #{runner.entity.name}"
        
        puts "\n" + "=" * 70
        puts "🔥 BOB v2.0 - FULL BENCHMARK"
        puts "=" * 70
        puts "Running #{Benchmarks::BusinessBenchmarkV2.all_tasks.size} tasks"
        puts ""

        Benchmarks::BusinessBenchmarkV2::CATEGORIES.each do |category_key, category_name|
          tasks = Benchmarks::BusinessBenchmarkV2.tasks_by_category(category_key)
          next if tasks.empty?
          
          puts "📁 #{category_name} (#{tasks.size} tasks)"
          tasks.each_with_index do |task, idx|
            print "  #{idx + 1}. #{task[:name].truncate(40)}... "
            result = runner.run_task(task, use_scout: true)
            runner.results << result
            
            status = result[:success] ? "✓" : "✗"
            time = "(#{result[:elapsed_ms]}ms)"
            tools = result[:tools_used]&.any? ? " 🔧#{result[:tools_used].size}" : ""
            agents = result[:agents_used]&.any? ? " 🤖#{result[:agents_used].size}" : ""
            assets = result[:created_assets]&.values&.flatten&.size.to_i
            assets_str = assets > 0 ? " 📦#{assets}" : ""
            puts "#{status} #{time}#{tools}#{agents}#{assets_str}"
            sleep(0.3)
          end
          puts ""
        end
        runner.generate_report
      end

      desc "Run V2 extreme challenges only"
      task :extreme => :environment do
        runner = Benchmarks::BusinessBenchmarkRunner.new(use_test_env: true, cleanup_before: true)
        puts "Using test environment: #{runner.entity.name}"
        
        tasks = Benchmarks::BusinessBenchmarkV2.extreme_tasks
        
        puts "\n" + "=" * 70
        puts "🔥🔥🔥 EXTREME CHALLENGES - NEARLY IMPOSSIBLE 🔥🔥🔥"
        puts "=" * 70
        puts "Running #{tasks.size} extreme multi-agent orchestration tasks"
        puts "These are designed to push the system to its limits!"
        puts ""

        tasks.each_with_index do |task, idx|
          puts "-" * 70
          puts "#{idx + 1}/#{tasks.size}: #{task[:name]}"
          puts "Request: #{task[:request].truncate(200)}"
          puts ""
          
          result = runner.run_task(task, use_scout: true)
          runner.results << result
          
          puts ""
          puts "Result: #{result[:success] ? '✅ SUCCESS' : '❌ FAILED'}"
          puts "Time: #{result[:elapsed_ms]}ms"
          puts "Tools used: #{result[:tools_used]&.join(', ') || 'none'}"
          puts "Agents used: #{result[:agents_used]&.join(', ') || 'none'}"
          
          if result[:created_assets]
            result[:created_assets].each do |type, items|
              puts "#{type}: #{items.size} created" if items.any?
            end
          end
          
          puts ""
          sleep(1) # Give more time between extreme tasks
        end
        
        puts "=" * 70
        runner.generate_report
      end

      desc "Run single V2 task"
      task :single, [:task_id] => :environment do |t, args|
        task_id = args[:task_id]
        
        unless task_id
          puts "Usage: rake benchmark:business:v2:single[task_id]"
          puts "Example: rake benchmark:business:v2:single[extreme_001]"
          next
        end

        task = Benchmarks::BusinessBenchmarkV2.task(task_id)
        unless task
          puts "❌ Task '#{task_id}' not found"
          puts "Available extreme tasks:"
          Benchmarks::BusinessBenchmarkV2.extreme_tasks.each do |t|
            puts "  #{t[:id]}: #{t[:name]}"
          end
          next
        end

        runner = Benchmarks::BusinessBenchmarkRunner.new(use_test_env: true, cleanup_before: false)

        puts "\n" + "=" * 70
        puts "🔥 Running: #{task[:name]}"
        puts "=" * 70
        puts ""
        puts "Scenario: #{task[:scenario]}"
        puts ""
        puts "Request:"
        puts task[:request]
        puts ""
        puts "Rubric:"
        task[:rubric].each { |r| puts "  • #{r}" }
        puts ""
        puts "-" * 70
        
        result = runner.run_task(task, use_scout: true)
        
        puts ""
        puts "=" * 70
        puts "RESULTS"
        puts "=" * 70
        puts "Success: #{result[:success]}"
        puts "Time: #{result[:elapsed_ms]}ms"
        puts ""
        puts "Tools used: #{result[:tools_used]&.join(', ') || 'none'}"
        puts "Agents used: #{result[:agents_used]&.join(', ') || 'none'}"
        puts "Delegated jobs: #{result[:delegated_jobs]&.join(', ') || 'none'}"
        puts ""
        
        if result[:created_assets]
          puts "Created Assets:"
          result[:created_assets].each do |type, items|
            if items.any?
              puts "  #{type}:"
              items.each { |item| puts "    - #{item.inspect}" }
            end
          end
        end
        
        puts ""
        puts "Response:"
        puts result[:response].to_s[0..2000]
        puts "=" * 70
      end
    end
  end
end

