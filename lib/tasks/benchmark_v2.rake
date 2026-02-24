# frozen_string_literal: true

namespace :benchmark do
  namespace :v2 do
    desc "List all registered scenarios"
    task list: :environment do
      puts "\n📊 Benchmark V2 Scenario Library"
      puts "=" * 70

      Benchmarks::V2::Scenario::LEVELS.each do |level|
        scenarios = Benchmarks::V2::ScenarioLibrary.by_level(level)
        next if scenarios.empty?

        puts "\n#{level} - #{level_description(level)} (#{scenarios.size} scenarios)"
        puts "-" * 50

        scenarios.each do |s|
          core_badge = s.core? ? " [CORE]" : ""
          puts "  #{s.id}#{core_badge}"
          puts "    #{s.name}"
          puts "    Category: #{s.category} | Messages: #{s.messages.size} | Assertions: #{s.assertions.size}"
        end
      end

      puts "\n📈 Total: #{Benchmarks::V2::ScenarioLibrary.count} scenarios"
      puts "   Core suite: #{Benchmarks::V2::ScenarioLibrary.core_suite.size} scenarios"
    end

    desc "Run core benchmark suite (MODEL=claude-sonnet-4-6 to override model)"
    task run: :environment do
      entity = Entity.find_by(slug: "amos-labs") || Entity.first
      user = entity&.users&.first
      abort "No entity/user found" unless entity && user

      model = ENV["MODEL"].presence
      display_model = model || V3::AgentLoop::DEFAULT_AUTO_MODEL
      puts "\n🚀 Running Benchmark V2 Core Suite..."
      puts "   Entity: #{entity.name}"
      puts "   Model: #{display_model}#{model ? ' (override)' : ' (default)'}"
      puts "   Git commit: #{`git rev-parse --short HEAD 2>/dev/null`.strip}"
      puts ""

      runner = Benchmarks::V2::Runner.new(entity: entity, user: user, model: model)
      results = runner.run_suite_with_progress(:core) { |r| print_scenario_result(r) }

      print_summary(results, display_model)
    end

    desc "Run a specific scenario (MODEL=claude-sonnet-4-6 to override model)"
    task :scenario, [:id] => :environment do |_t, args|
      abort "Usage: rails benchmark:v2:scenario[scenario_id]" unless args[:id]

      entity = Entity.find_by(slug: "amos-labs") || Entity.first
      user = entity&.users&.first
      abort "No entity/user found" unless entity && user

      scenario_id = args[:id].to_sym
      abort "Unknown scenario: #{scenario_id}" unless Benchmarks::V2::ScenarioLibrary.get(scenario_id)

      model = ENV["MODEL"].presence
      display_model = model || V3::AgentLoop::DEFAULT_AUTO_MODEL
      puts "\n🚀 Running scenario: #{scenario_id} (model: #{display_model})..."

      runner = Benchmarks::V2::Runner.new(entity: entity, user: user, model: model)
      results = runner.run_suite_with_progress(:single, scenario_ids: [scenario_id]) { |r| print_scenario_result(r) }

      print_summary(results, display_model)
    end

    desc "Run multiple scenarios by ID (SCENARIOS=id1,id2,id3 MODEL=claude-sonnet-4-6)"
    task pick: :environment do
      scenario_list = ENV["SCENARIOS"].presence
      abort "Usage: SCENARIOS=id1,id2,id3 rails benchmark:v2:pick" unless scenario_list

      entity = Entity.find_by(slug: "amos-labs") || Entity.first
      user = entity&.users&.first
      abort "No entity/user found" unless entity && user

      ids = scenario_list.split(",").map(&:strip).map(&:to_sym)
      ids.each do |id|
        abort "Unknown scenario: #{id}. Run 'rails benchmark:v2:list' to see available IDs." unless Benchmarks::V2::ScenarioLibrary.get(id)
      end

      model = ENV["MODEL"].presence
      display_model = model || V3::AgentLoop::DEFAULT_AUTO_MODEL
      puts "\n🚀 Running #{ids.size} selected scenarios (model: #{display_model})..."

      runner = Benchmarks::V2::Runner.new(entity: entity, user: user, model: model)
      results = runner.run_suite_with_progress(:single, scenario_ids: ids) { |r| print_scenario_result(r) }

      print_summary(results, display_model)
    end

    desc "Run full benchmark suite (MODEL=claude-sonnet-4-6 to override model)"
    task full: :environment do
      entity = Entity.find_by(slug: "amos-labs") || Entity.first
      user = entity&.users&.first
      abort "No entity/user found" unless entity && user

      model = ENV["MODEL"].presence
      display_model = model || V3::AgentLoop::DEFAULT_AUTO_MODEL
      puts "\n🚀 Running FULL Benchmark V2 Suite (model: #{display_model})..."

      runner = Benchmarks::V2::Runner.new(entity: entity, user: user, model: model)
      results = runner.run_suite_with_progress(:full) { |r| print_scenario_result(r) }

      print_summary(results, display_model)
    end

    desc "Compare latest benchmark run to baseline"
    task compare: :environment do
      latest = BenchmarkRun
                 .where(run_type: "v2_benchmark")
                 .where.not(benchmark_category: "baseline_update")
                 .where.not(completed_at: nil)
                 .order(created_at: :desc)
                 .first

      abort "No v2 benchmark runs found" unless latest

      comparator = Benchmarks::V2::Comparator.new
      report = comparator.compare(latest)

      puts "\n📊 Benchmark Comparison"
      puts "=" * 70
      puts report[:scorecard]

      if report[:regressions].any?
        puts "\n⚠️  #{report[:regressions].size} REGRESSION(S) DETECTED"
      end

      if report[:improvements].any?
        puts "\n✅ #{report[:improvements].size} improvement(s)"
      end
    end

    desc "Show difficulty and mastery report"
    task difficulty: :environment do
      dm = Benchmarks::V2::DifficultyManager.new
      report = dm.comfort_report

      puts "\n📊 Benchmark Difficulty Report"
      puts "=" * 70
      puts "Mastered: #{report[:mastered_count]}/#{report[:total_scenarios]} (#{report[:mastery_rate]}%)"
      puts "Comfort zone: #{report[:in_comfort_zone] ? '⚠️  YES - benchmarks too easy!' : '✅ No'}"
      puts "Unmastered avg score: #{report[:weighted_unmastered_avg]}"
      puts "\nRecent averages: #{report[:recent_averages].join(', ')}"
      puts "\n💡 #{report[:recommendation]}"

      puts "\n📊 Level Distribution:"
      dm.level_distribution.each do |level, data|
        bar = "█" * data[:total] + "░" * (10 - data[:total])
        puts "  #{level}: #{bar} #{data[:mastered]}/#{data[:total]} mastered (weight: #{data[:weight]}x)"
      end
    end

    desc "Mine failed user conversations for new scenarios"
    task :mine, [:days] => :environment do |_t, args|
      days = (args[:days] || 7).to_i

      puts "\n⛏️  Mining failed conversations (last #{days} days)..."

      miner = Benchmarks::V2::ScenarioMiner.new(days: days)
      candidates = miner.mine

      if candidates.empty?
        puts "No mineable failures found."
        next
      end

      puts "Found #{candidates.size} candidate scenarios:\n"

      candidates.each_with_index do |c, i|
        puts "#{i + 1}. #{c[:name]}"
        puts "   Level: #{c[:level]} | Category: #{c[:category]} | Source: #{c[:failure_type]}"
        puts "   #{c[:description]}"
        puts ""
      end
    end

    def print_scenario_result(r)
      status = r[:score][:passed] ? "✅" : "❌"
      puts ""
      puts "#{status} #{r[:scenario_id]} (#{r[:level]})"
      puts "   Score: #{r[:score][:total_score]}/#{r[:score][:max_score]} " \
           "(assertions: #{r[:score][:assertion_score]}/#{r[:score][:assertion_max]}, " \
           "judge: #{r[:score][:judge_score]}/#{r[:score][:judge_max]})"
      puts "   Time: #{(r[:duration_ms] / 1000.0).round(1)}s"

      r[:score][:assertion_details]&.each do |detail|
        icon = detail[:passed] ? "  ✓" : "  ✗"
        puts "   #{icon} #{detail[:type]}: #{detail[:message]}"
      end

      if r[:score][:judge_reasoning].present?
        puts ""
        puts "   Judge: #{r[:score][:judge_reasoning]}"
      end

      if r[:score][:judge_breakdown].present? && r[:score][:judge_breakdown].is_a?(Hash)
        r[:score][:judge_breakdown].each do |criterion, data|
          next unless data.is_a?(Hash)
          puts "     #{criterion}: #{data['score'] || data[:score]}/#{data['max'] || data[:max]} — #{data['reasoning'] || data[:reasoning]}"
        end
      end
      puts ""
    end

    def print_summary(results, model = nil)
      puts "\n" + "=" * 70
      puts "📊 Summary"
      puts "=" * 70
      puts "Suite: #{results[:suite]}"
      puts "Model: #{model || V3::AgentLoop::DEFAULT_AUTO_MODEL}"
      puts "Git commit: #{results[:git_commit] || 'unknown'}"
      puts "Total scenarios: #{results[:total_scenarios]}"
      puts "Average score: #{results[:average_score]}/100"
      puts "Pass rate: #{results[:pass_rate]}%"
      puts "Duration: #{(results[:duration_ms] / 1000.0).round(1)}s"
      puts "Scoring: assertions #{Benchmarks::V2::Scorer::ASSERTION_MAX}/judge #{Benchmarks::V2::Scorer::JUDGE_MAX}"
      puts ""

      results[:scenario_results]&.each do |r|
        status = r[:score][:passed] ? "✅" : "❌"
        puts "  #{status} #{r[:scenario_id]}: #{r[:score][:total_score]}/100"
      end
      puts ""
    end

    def level_description(level)
      case level
      when :L1 then "Single step (regression check)"
      when :L2 then "Multi-step workflows (baseline)"
      when :L3 then "Complex orchestration (real-world)"
      when :L4 then "Adversarial / edge cases"
      when :L5 then "Mined from real failures"
      end
    end
  end
end
