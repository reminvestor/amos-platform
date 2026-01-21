# frozen_string_literal: true

# ============================================
# BUSINESS OPERATIONS BENCHMARK (BOB) v3.0
# "HARD MODE" - Multi-Dimensional Evaluation
# ============================================

namespace :benchmark do
  namespace :bob3 do
    desc "Show BOB v3.0 info"
    task :info => :environment do
      puts "\n" + "=" * 80
      puts "🏢 BUSINESS OPERATIONS BENCHMARK (BOB) v3.0 - HARD MODE"
      puts "=" * 80
      puts ""
      puts "Total tasks: #{Benchmarks::BusinessBenchmarkV3.total_tasks}"
      puts ""
      puts "DIFFICULTY TIERS:"
      Benchmarks::BusinessBenchmarkV3.difficulty_breakdown.each do |tier, count|
        tier_info = Benchmarks::BusinessBenchmarkV3::DIFFICULTY_TIERS[tier]
        expectation = (Benchmarks::BusinessBenchmarkRunnerV3::TIER_EXPECTATIONS[tier] * 100).round
        puts "  #{tier_info[:name]} (#{tier}): #{count} tasks - Expected: #{expectation}%+"
      end
      puts ""
      puts "CATEGORIES:"
      Benchmarks::BusinessBenchmarkV3.category_breakdown.each do |cat, count|
        cat_name = Benchmarks::BusinessBenchmarkV3::CATEGORIES[cat]
        puts "  #{cat_name}: #{count} tasks"
      end
      puts ""
      puts "SCORING DIMENSIONS:"
      Benchmarks::BusinessBenchmarkV3::SCORING_DIMENSIONS.each do |dim, config|
        puts "  #{dim.to_s.titleize}: #{(config[:weight] * 100).round}% weight"
      end
      puts ""
      puts "EXPECTED SCORE RANGES:"
      Benchmarks::BusinessBenchmarkV3.expected_score_range.each do |level, range|
        puts "  #{level.to_s.titleize.gsub('_', ' ')}: #{range.first}% - #{range.last}%"
      end
      puts ""
      puts "Commands:"
      puts "  rake benchmark:bob3:quick         # 2 tasks per tier (10 total)"
      puts "  rake benchmark:bob3:full          # All tasks"
      puts "  rake benchmark:bob3:tier[1]       # Run specific tier (1-5)"
      puts "  rake benchmark:bob3:category[x]   # Run specific category"
      puts "  rake benchmark:bob3:single[id]    # Run single task"
      puts "=" * 80
    end

    desc "Run quick BOB v3.0 benchmark (2 per tier)"
    task :quick => :environment do
      runner = Benchmarks::BusinessBenchmarkRunnerV3.new(use_test_env: true)
      puts "Using test environment: #{runner.entity.name}"
      runner.run_quick_benchmark(tasks_per_tier: 2)
    end

    desc "Run full BOB v3.0 benchmark"
    task :full => :environment do
      runner = Benchmarks::BusinessBenchmarkRunnerV3.new(use_test_env: true)
      puts "Using test environment: #{runner.entity.name}"
      runner.run_full_benchmark
    end

    desc "Run specific tier (1-5)"
    task :tier, [:tier_num] => :environment do |_, args|
      tier_num = args[:tier_num].to_i
      tier_key = "tier_#{tier_num}".to_sym

      unless Benchmarks::BusinessBenchmarkV3::DIFFICULTY_TIERS.key?(tier_key)
        puts "Invalid tier: #{tier_num}. Use 1-5."
        next
      end

      runner = Benchmarks::BusinessBenchmarkRunnerV3.new(use_test_env: true)
      puts "Running Tier #{tier_num} tasks..."
      runner.run_tier(tier_key)
      runner.generate_report
    end

    desc "Run specific category"
    task :category, [:cat] => :environment do |_, args|
      cat = args[:cat]&.to_sym

      unless Benchmarks::BusinessBenchmarkV3::CATEGORIES.key?(cat)
        puts "Invalid category: #{cat}"
        puts "Valid categories: #{Benchmarks::BusinessBenchmarkV3::CATEGORIES.keys.join(', ')}"
        next
      end

      runner = Benchmarks::BusinessBenchmarkRunnerV3.new(use_test_env: true)
      puts "Running #{cat} tasks..."
      runner.run_category(cat)
      runner.generate_report
    end

    desc "Run single task by ID"
    task :single, [:task_id] => :environment do |_, args|
      task_id = args[:task_id]

      task = Benchmarks::BusinessBenchmarkV3.task(task_id)
      unless task
        puts "Task not found: #{task_id}"
        puts "Available tasks:"
        Benchmarks::BusinessBenchmarkV3.all_tasks.each { |t| puts "  #{t[:id]}: #{t[:name]}" }
        next
      end

      runner = Benchmarks::BusinessBenchmarkRunnerV3.new(use_test_env: true)
      result = runner.run_single(task_id)

      puts "\n" + "=" * 60
      puts "TASK: #{task[:name]}"
      puts "TIER: #{task[:tier]}"
      puts "CATEGORY: #{task[:category]}"
      puts "=" * 60
      puts ""
      puts "RESULT: #{result[:passed] ? '✓ PASSED' : '✗ FAILED'}"
      puts "SCORE: #{(result[:total_score] * 100).round(1)}%"
      puts "LATENCY: #{result[:latency_ms]}ms"
      puts ""
      puts "DIMENSION SCORES:"
      result[:dimension_scores].each do |dim, score|
        puts "  #{dim}: #{(score * 100).round(1)}%"
      end
      puts ""
      puts "TOOLS USED: #{result[:tools_used].join(', ')}"
      puts ""
      if result[:verification_details].present?
        puts "VERIFICATION: #{result[:verification_details].inspect}"
        puts ""
      end
      if result[:errors]&.any?
        puts "ERRORS: #{result[:errors].join(', ')}"
        puts ""
      end
      puts "RESPONSE:"
      puts result[:response].to_s.truncate(500)
      puts "=" * 60
    end

    desc "List all tasks"
    task :list => :environment do
      Benchmarks::BusinessBenchmarkV3::DIFFICULTY_TIERS.each do |tier_key, tier_info|
        tasks = Benchmarks::BusinessBenchmarkV3.tasks_by_tier(tier_key)
        next if tasks.empty?

        puts "\n#{tier_info[:name]} (#{tier_key}):"
        puts "-" * 40
        tasks.each do |t|
          puts "  #{t[:id]}: #{t[:name]} [#{t[:category]}]"
        end
      end
    end

    desc "Export results to JSON"
    task :export => :environment do
      results_file = Rails.root.join('tmp', 'benchmarks', "bob3_results_#{Time.current.strftime('%Y%m%d_%H%M')}.json")
      FileUtils.mkdir_p(File.dirname(results_file))

      # Run full benchmark
      runner = Benchmarks::BusinessBenchmarkRunnerV3.new(use_test_env: true)
      runner.run_full_benchmark

      # Export
      export_data = {
        benchmark: 'BOB v3.0',
        version: Benchmarks::BusinessBenchmarkV3::VERSION,
        run_at: Time.current.iso8601,
        total_tasks: runner.results.count,
        passed: runner.results.count { |r| r[:passed] },
        avg_score: (runner.results.sum { |r| r[:total_score] } / runner.results.count).round(4),
        tier_breakdown: Benchmarks::BusinessBenchmarkV3.difficulty_breakdown,
        results: runner.results
      }

      File.write(results_file, JSON.pretty_generate(export_data))
      puts "\nExported to: #{results_file}"
    end
  end
end





