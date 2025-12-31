# frozen_string_literal: true

# ============================================
# BUSINESS OPERATIONS BENCHMARK (BOB) v4.0
# "NIGHTMARE MODE" - Factory Integration Testing
# ============================================

namespace :benchmark do
  namespace :bob4 do
    desc "Show BOB v4.0 info"
    task :info => :environment do
      puts "\n" + "=" * 80
      puts "🏢 BUSINESS OPERATIONS BENCHMARK (BOB) v4.0 - NIGHTMARE MODE"
      puts "=" * 80
      puts ""
      puts "Total tasks: #{Benchmarks::BusinessBenchmarkV4.total_tasks}"
      puts ""
      puts "DIFFICULTY TIERS (stricter expectations):"
      Benchmarks::BusinessBenchmarkV4.difficulty_breakdown.each do |tier, count|
        tier_info = Benchmarks::BusinessBenchmarkV4::DIFFICULTY_TIERS[tier]
        expectation = (tier_info[:expected] * 100).round
        puts "  #{tier_info[:name]} (#{tier}): #{count} tasks - Expected: #{expectation}%+"
      end
      puts ""
      puts "CATEGORIES:"
      Benchmarks::BusinessBenchmarkV4.category_breakdown.each do |cat, count|
        cat_name = Benchmarks::BusinessBenchmarkV4::CATEGORIES[cat]
        puts "  #{cat_name}: #{count} tasks"
      end
      puts ""
      puts "VERIFICATION COVERAGE:"
      Benchmarks::BusinessBenchmarkV4.verification_coverage.each do |vtype, count|
        level = Benchmarks::BusinessBenchmarkV4::VERIFICATION_TYPES.dig(vtype, :level) || '?'
        puts "  L#{level} #{vtype}: #{count} tasks"
      end
      puts ""
      puts "SCORING DIMENSIONS:"
      Benchmarks::BusinessBenchmarkV4::SCORING_DIMENSIONS.each do |dim, config|
        puts "  #{dim.to_s.titleize}: #{(config[:weight] * 100).round}% weight"
      end
      puts ""
      puts "EXPECTED SCORE RANGES:"
      Benchmarks::BusinessBenchmarkV4.expected_score_range.each do |level, range|
        puts "  #{level.to_s.titleize.gsub('_', ' ')}: #{range.first}% - #{range.last}%"
      end
      puts ""
      puts "Commands:"
      puts "  rake benchmark:bob4:quick         # Quick sample (2 per tier)"
      puts "  rake benchmark:bob4:full          # All tasks"
      puts "  rake benchmark:bob4:factories     # Factory integration tests only"
      puts "  rake benchmark:bob4:tier[1]       # Run specific tier (1-5)"
      puts "  rake benchmark:bob4:category[x]   # Run specific category"
      puts "  rake benchmark:bob4:single[id]    # Run single task"
      puts "  rake benchmark:bob4:compare       # Run both v3 and v4, compare"
      puts "=" * 80
    end

    desc "Run quick BOB v4.0 benchmark (2 per tier)"
    task :quick => :environment do
      runner = Benchmarks::BusinessBenchmarkRunnerV4.new(use_test_env: true)
      puts "Using test environment: #{runner.entity.name}"
      runner.run_quick_benchmark(tasks_per_tier: 2)
    end

    desc "Run full BOB v4.0 benchmark"
    task :full => :environment do
      verbose = ENV['VERBOSE'] == 'true' || ENV['V'] == '1'
      puts ""
      puts "💡 TIP: For async tests (agent delegation, etc.), run Solid Queue first:"
      puts "   bundle exec rake solid_queue:start"
      puts ""
      runner = Benchmarks::BusinessBenchmarkRunnerV4.new(use_test_env: true, verbose: verbose)
      puts "Using test environment: #{runner.entity.name}"
      puts "Verbose mode: #{verbose ? 'ON' : 'OFF'} (set VERBOSE=true to enable)" unless verbose
      runner.run_full_benchmark
    end

    desc "Run factory integration tests only"
    task :factories => :environment do
      verbose = ENV['VERBOSE'] == 'true' || ENV['V'] == '1'
      puts ""
      puts "💡 TIP: Factory tests require Solid Queue for async operations:"
      puts "   bundle exec rake solid_queue:start"
      puts ""
      runner = Benchmarks::BusinessBenchmarkRunnerV4.new(use_test_env: true, verbose: verbose)
      puts "Using test environment: #{runner.entity.name}"
      puts "Verbose mode: #{verbose ? 'ON' : 'OFF'} (set VERBOSE=true to enable)" unless verbose
      runner.run_factories
      runner.generate_report
    end

    desc "Run specific tier (1-5)"
    task :tier, [:tier_num] => :environment do |_, args|
      tier_num = args[:tier_num].to_i
      tier_key = "tier_#{tier_num}".to_sym

      unless Benchmarks::BusinessBenchmarkV4::DIFFICULTY_TIERS.key?(tier_key)
        puts "Invalid tier: #{tier_num}. Use 1-5."
        next
      end

      runner = Benchmarks::BusinessBenchmarkRunnerV4.new(use_test_env: true)
      puts "Running Tier #{tier_num} tasks..."
      runner.run_tier(tier_key)
      runner.generate_report
    end

    desc "Run specific category"
    task :category, [:cat] => :environment do |_, args|
      cat = args[:cat]&.to_sym

      unless Benchmarks::BusinessBenchmarkV4::CATEGORIES.key?(cat)
        puts "Invalid category: #{cat}"
        puts "Valid categories: #{Benchmarks::BusinessBenchmarkV4::CATEGORIES.keys.join(', ')}"
        next
      end

      runner = Benchmarks::BusinessBenchmarkRunnerV4.new(use_test_env: true)
      puts "Running #{cat} tasks..."
      runner.run_category(cat)
      runner.generate_report
    end

    desc "Run single task by ID"
    task :single, [:task_id] => :environment do |_, args|
      task_id = args[:task_id]

      task = Benchmarks::BusinessBenchmarkV4.task(task_id)
      unless task
        puts "Task not found: #{task_id}"
        puts "Available tasks:"
        Benchmarks::BusinessBenchmarkV4.all_tasks.each { |t| puts "  #{t[:id]}: #{t[:name]} [#{t[:category]}]" }
        next
      end

      runner = Benchmarks::BusinessBenchmarkRunnerV4.new(use_test_env: true)
      result = runner.run_single(task_id)

      puts "\n" + "=" * 60
      puts "TASK: #{task[:name]}"
      puts "TIER: #{task[:tier]}"
      puts "CATEGORY: #{task[:category]}"
      puts "VERIFICATION: #{task[:verification]} (L#{Benchmarks::BusinessBenchmarkV4::VERIFICATION_TYPES.dig(task[:verification], :level) || '?'})"
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
      puts "TOOLS USED: #{(result[:tools_used] || []).join(', ')}"
      puts ""
      if result[:verification].present?
        puts "VERIFICATION DETAILS:"
        puts "  Type: #{result[:verification][:type]}"
        puts "  Level: L#{result[:verification][:level]}"
        puts "  Passed: #{result[:verification][:passed]}"
        if result[:verification][:ground_truth]
          puts "  Expected: #{result[:verification][:ground_truth].inspect.truncate(100)}"
        end
        if result[:verification][:actual]
          puts "  Actual: #{result[:verification][:actual].inspect.truncate(100)}"
        end
        if result[:verification][:details].present?
          puts "  Details: #{result[:verification][:details].inspect.truncate(200)}"
        end
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
      Benchmarks::BusinessBenchmarkV4::DIFFICULTY_TIERS.each do |tier_key, tier_info|
        tasks = Benchmarks::BusinessBenchmarkV4.tasks_by_tier(tier_key)
        next if tasks.empty?

        puts "\n#{tier_info[:name]} (#{tier_key}) - Expected: #{(tier_info[:expected] * 100).round}%:"
        puts "-" * 40
        tasks.each do |t|
          vtype = t[:verification]
          level = Benchmarks::BusinessBenchmarkV4::VERIFICATION_TYPES.dig(vtype, :level) || '?'
          puts "  #{t[:id]}: #{t[:name]} [#{t[:category]}] (L#{level})"
        end
      end
    end

    desc "Compare BOB v3 and v4 results"
    task :compare => :environment do
      puts "\n🔬 BENCHMARK COMPARISON: BOB v3.0 vs v4.0"
      puts "=" * 80
      puts ""

      # Run v3
      puts "Running BOB v3.0..."
      runner_v3 = Benchmarks::BusinessBenchmarkRunnerV3.new(use_test_env: true)
      runner_v3.run_quick_benchmark(tasks_per_tier: 2)
      v3_score = (runner_v3.results.sum { |r| r[:total_score] } / runner_v3.results.count * 100).round(1)
      v3_passed = runner_v3.results.count { |r| r[:passed] }

      puts "\n"

      # Run v4
      puts "Running BOB v4.0..."
      runner_v4 = Benchmarks::BusinessBenchmarkRunnerV4.new(use_test_env: true)
      runner_v4.run_quick_benchmark(tasks_per_tier: 2)
      v4_score = (runner_v4.results.sum { |r| r[:total_score] } / runner_v4.results.count * 100).round(1)
      v4_passed = runner_v4.results.count { |r| r[:passed] }

      puts "\n"
      puts "=" * 80
      puts "COMPARISON RESULTS"
      puts "=" * 80
      puts ""
      puts "                    BOB v3.0    BOB v4.0    Delta"
      puts "  Passed:           #{v3_passed}/#{runner_v3.results.count}         #{v4_passed}/#{runner_v4.results.count}         #{v4_passed - v3_passed >= 0 ? '+' : ''}#{v4_passed - v3_passed}"
      puts "  Average Score:    #{v3_score}%       #{v4_score}%       #{v4_score - v3_score >= 0 ? '+' : ''}#{(v4_score - v3_score).round(1)}%"
      puts ""
      puts "Note: v4.0 has stricter expectations and factory integration tests."
      puts "A lower v4 score indicates harder tests, not worse performance."
      puts "=" * 80
    end

    desc "Export results to JSON"
    task :export => :environment do
      results_file = Rails.root.join('tmp', 'benchmarks', "bob4_results_#{Time.current.strftime('%Y%m%d_%H%M')}.json")
      FileUtils.mkdir_p(File.dirname(results_file))

      runner = Benchmarks::BusinessBenchmarkRunnerV4.new(use_test_env: true)
      runner.run_full_benchmark

      export_data = {
        benchmark: 'BOB v4.0',
        version: Benchmarks::BusinessBenchmarkV4::VERSION,
        run_at: Time.current.iso8601,
        total_tasks: runner.results.count,
        passed: runner.results.count { |r| r[:passed] },
        avg_score: (runner.results.sum { |r| r[:total_score] } / runner.results.count).round(4),
        tier_breakdown: Benchmarks::BusinessBenchmarkV4.difficulty_breakdown,
        verification_coverage: Benchmarks::BusinessBenchmarkV4.verification_coverage,
        results: runner.results.map do |r|
          r.merge(verification: r[:verification]&.except(:actual)) # Don't serialize AR objects
        end
      }

      File.write(results_file, JSON.pretty_generate(export_data))
      puts "\nExported to: #{results_file}"
    end
  end
end

