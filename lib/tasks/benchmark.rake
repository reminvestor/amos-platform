# frozen_string_literal: true

namespace :benchmark do
  desc "Show available benchmarks"
  task summary: :environment do
    puts "\n" + "=" * 60
    puts "📊 AMOS BENCHMARK SUMMARY"
    puts "=" * 60

    # Agent collaboration benchmarks
    collab_summary = Collaboration::PublicBenchmarks.summary
    puts "\n🤝 Agent Collaboration Benchmarks:"
    puts "  Total: #{collab_summary[:total]}"
    puts "  By Category: #{collab_summary[:by_category].map { |k, v| "#{k}(#{v})" }.join(', ')}"
    puts "  By Difficulty: #{collab_summary[:by_difficulty].map { |k, v| "#{k}(#{v})" }.join(', ')}"
    puts "  Requiring tools: #{collab_summary[:requiring_tools]}"
    puts "  Requiring collaboration: #{collab_summary[:requiring_collaboration]}"

    # System-wide benchmarks
    system_summary = Collaboration::SystemBenchmarks.summary
    puts "\n🖥️  System-Wide Benchmarks:"
    puts "  Total: #{system_summary[:total]}"
    puts "  By Category: #{system_summary[:by_category].map { |k, v| "#{k}(#{v})" }.join(', ')}"
    puts "  By Difficulty: #{system_summary[:by_difficulty].map { |k, v| "#{k}(#{v})" }.join(', ')}"
    puts "  Requiring integrations: #{system_summary[:requires_integration]}"
    puts "  Requiring documents: #{system_summary[:requires_documents]}"
    puts "  Requiring collaboration: #{system_summary[:requires_collaboration]}"

    puts "\n" + "=" * 60
    puts "📚 Public Benchmark References:"
    puts "  • GAIA: Real-world assistant tasks"
    puts "    https://huggingface.co/datasets/gaia-benchmark/GAIA"
    puts "  • BFCL: Berkeley Function Calling Leaderboard"
    puts "    https://gorilla.cs.berkeley.edu/leaderboard.html"
    puts "  • ToolBench: Tool learning benchmark"
    puts "    https://github.com/OpenBMB/ToolBench"
    puts "  • AgentBench: Multi-agent evaluation"
    puts "    https://github.com/THUDM/AgentBench"
    puts "  • REALM-Bench: Real-world planning"
    puts "    https://arxiv.org/abs/2502.18836"
    puts "  • MultiAgentBench: Collaboration evaluation"
    puts "    https://github.com/MultiAgentBench"
    puts "=" * 60
  end

  # ============================================
  # SYSTEM-WIDE BENCHMARKS
  # ============================================

  desc "Run quick system validation (5-10 essential tests)"
  task system_quick: :environment do
    entity = Entity.first
    user = User.first

    unless entity && user
      puts "❌ No entity or user found"
      next
    end

    runner = Collaboration::SystemBenchmarkRunner.new(entity: entity, user: user)
    runner.run_quick_validation(verbose: true)
  end

  desc "Run full system-wide benchmark suite"
  task system_full: :environment do
    entity = Entity.first
    user = User.first

    unless entity && user
      puts "❌ No entity or user found"
      next
    end

    runner = Collaboration::SystemBenchmarkRunner.new(entity: entity, user: user)
    runner.run_full_suite(verbose: true)
  end

  desc "Run system benchmark for a specific category"
  task :system_category, [:category] => :environment do |t, args|
    category = args[:category]&.to_sym

    unless category
      puts "Usage: rake benchmark:system_category[category]"
      puts "Available categories: #{Collaboration::SystemBenchmarks.all_tests.keys.join(', ')}"
      next
    end

    entity = Entity.first
    user = User.first

    unless entity && user
      puts "❌ No entity or user found"
      next
    end

    runner = Collaboration::SystemBenchmarkRunner.new(entity: entity, user: user)
    runner.run_category(category, verbose: true)
    runner.send(:generate_summary, verbose: true)
  end

  desc "Run a single system test by ID"
  task :system_test, [:test_id] => :environment do |t, args|
    test_id = args[:test_id]

    unless test_id
      puts "Usage: rake benchmark:system_test[test_id]"
      puts "Example: rake benchmark:system_test[tool_001]"
      next
    end

    entity = Entity.first
    user = User.first

    unless entity && user
      puts "❌ No entity or user found"
      next
    end

    runner = Collaboration::SystemBenchmarkRunner.new(entity: entity, user: user)
    result = runner.run_single_test_by_id(test_id)

    if result[:error] && result[:error].include?('not found')
      puts "❌ #{result[:error]}"
    else
      status = result[:passed] ? '✓ PASSED' : '✗ FAILED'
      puts "\n#{status}: #{result[:name]}"
      puts "  Time: #{result[:execution_time_ms]}ms"
      puts "  Answer: #{result[:answer]&.truncate(100)}" if result[:answer]
      puts "  Error: #{result[:error]}" if result[:error]
    end
  end

  desc "Export system benchmark results to JSON"
  task :system_export_json, [:filename] => :environment do |t, args|
    entity = Entity.first
    user = User.first

    unless entity && user
      puts "❌ No entity or user found"
      next
    end

    runner = Collaboration::SystemBenchmarkRunner.new(entity: entity, user: user)
    runner.run_full_suite(verbose: false)

    filename = args[:filename] || "system_benchmark_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
    filepath = Rails.root.join('tmp', filename)

    File.write(filepath, runner.export_to_json)
    puts "✅ Results exported to: #{filepath}"
  end

  desc "Export system benchmark results to Markdown"
  task :system_export_md, [:filename] => :environment do |t, args|
    entity = Entity.first
    user = User.first

    unless entity && user
      puts "❌ No entity or user found"
      next
    end

    runner = Collaboration::SystemBenchmarkRunner.new(entity: entity, user: user)
    runner.run_full_suite(verbose: false)

    filename = args[:filename] || "SYSTEM_BENCHMARK_REPORT.md"
    filepath = Rails.root.join('docs', filename)

    File.write(filepath, runner.export_to_markdown)
    puts "✅ Report saved to: #{filepath}"
  end

  # ============================================
  # COMBINED BENCHMARKS
  # ============================================

  desc "Run ALL benchmarks (collaboration + system)"
  task all: :environment do
    entity = Entity.first
    user = User.first

    unless entity && user
      puts "❌ No entity or user found"
      next
    end

    puts "\n" + "=" * 60
    puts "🚀 AMOS COMPLETE BENCHMARK SUITE"
    puts "=" * 60
    puts "Running all benchmarks across the entire platform..."
    puts ""

    start_time = Time.current
    all_results = { collaboration: {}, system: {} }

    # Run collaboration benchmarks
    puts "📦 Part 1: Agent Collaboration Benchmarks"
    puts "-" * 40

    collab_runner = Collaboration::BenchmarkRunner.new(entity: entity, user: user)
    [:gsm8k, :hotpot, :tool_use].each do |category|
      benchmarks = Collaboration::PublicBenchmarks.get_benchmark(category)
      agent = pick_agent_for_category(category, entity)
      next unless agent

      correct = 0
      benchmarks.each do |benchmark|
        result = collab_runner.run_single_benchmark(
          agent_slug: agent.slug,
          task_id: benchmark[:id],
          allow_collaboration: true
        )
        correct += 1 if result[:correct]
        print result[:correct] ? '.' : 'x'
      end
      puts ""

      all_results[:collaboration][category] = {
        agent: agent.slug,
        total: benchmarks.size,
        correct: correct,
        accuracy: (correct.to_f / benchmarks.size * 100).round(1)
      }
    end

    # Run system benchmarks
    puts "\n📦 Part 2: System-Wide Benchmarks"
    puts "-" * 40

    system_runner = Collaboration::SystemBenchmarkRunner.new(entity: entity, user: user)
    system_runner.run_full_suite(verbose: true)
    all_results[:system] = system_runner.send(:generate_summary, verbose: false)

    # Final summary
    elapsed = Time.current - start_time

    puts "\n" + "=" * 60
    puts "🏆 COMPLETE BENCHMARK RESULTS"
    puts "=" * 60
    puts "Total Duration: #{elapsed.round(1)}s"
    puts ""

    puts "Agent Collaboration:"
    all_results[:collaboration].each do |cat, results|
      puts "  #{cat}: #{results[:correct]}/#{results[:total]} (#{results[:accuracy]}%)"
    end

    total_collab = all_results[:collaboration].values.sum { |r| r[:total] }
    correct_collab = all_results[:collaboration].values.sum { |r| r[:correct] }
    puts "  Overall: #{correct_collab}/#{total_collab} (#{(correct_collab.to_f / total_collab * 100).round(1)}%)" if total_collab > 0

    puts ""
    puts "System-Wide:"
    puts "  Tests: #{all_results[:system][:total_tests]}"
    puts "  Passed: #{all_results[:system][:passed]} (#{all_results[:system][:pass_rate]}%)"
    puts "  Failed: #{all_results[:system][:failed]}"

    puts ""
    puts "=" * 60
  end

  # ============================================
  # EXTERNAL PUBLIC BENCHMARKS
  # ============================================

  desc "Show external benchmark sources"
  task external_summary: :environment do
    summary = Collaboration::ExternalBenchmarks.summary

    puts "\n" + "=" * 60
    puts "📚 EXTERNAL PUBLIC BENCHMARKS"
    puts "=" * 60
    puts "Total samples: #{summary[:total]}"
    puts ""
    puts "By Source:"
    summary[:by_source].each do |source, count|
      puts "  #{source.to_s.upcase}: #{count} samples"
    end
    puts ""
    puts "Requiring tools: #{summary[:requiring_tools]}"
    puts ""
    puts "Sources:"
    puts "  • GAIA: Real-world assistant tasks (HuggingFace)"
    puts "  • BFCL: Berkeley Function Calling Leaderboard"
    puts "  • ToolBench: API tool usage benchmark"
    puts "  • SimpleQA: Factual accuracy (OpenAI)"
    puts "  • MMLU: Multitask language understanding"
    puts "  • Code: HumanEval-inspired code tasks"
    puts "=" * 60
  end

  desc "Run external benchmark suite"
  task :external, [:source, :agent_slug] => :environment do |t, args|
    source = args[:source]&.to_sym
    agent_slug = args[:agent_slug] || 'scout'

    entity = Entity.first
    user = User.first

    unless entity && user
      puts "❌ No entity or user found"
      next
    end

    agent = AgentPlugin.find_by(slug: agent_slug, entity: entity)
    unless agent
      puts "❌ Agent '#{agent_slug}' not found"
      next
    end

    benchmarks = if source
      Collaboration::ExternalBenchmarks.get_benchmark(source)
    else
      Collaboration::ExternalBenchmarks.all_benchmarks.values.flatten
    end

    if benchmarks.empty?
      puts "❌ No benchmarks found for source: #{source}"
      puts "Available sources: #{Collaboration::ExternalBenchmarks.all_benchmarks.keys.join(', ')}"
      next
    end

    puts "\n" + "=" * 60
    puts "🌐 EXTERNAL BENCHMARK RUN"
    puts "=" * 60
    puts "Source: #{source || 'ALL'}"
    puts "Agent: #{agent.name} (#{agent_slug})"
    puts "Tasks: #{benchmarks.size}"
    puts ""

    runner = Collaboration::BenchmarkRunner.new(entity: entity, user: user)
    results = { correct: 0, total: 0, by_source: {} }

    benchmarks.each_with_index do |benchmark, i|
      source_name = benchmark[:source]
      results[:by_source][source_name] ||= { correct: 0, total: 0 }

      puts "#{i + 1}. [#{source_name}] #{benchmark[:question].truncate(60)}"

      begin
        result = runner.run_single_benchmark(
          agent_slug: agent_slug,
          task_id: benchmark[:id],
          allow_collaboration: true,
          custom_question: benchmark[:question]
        )

        # Validate using external benchmark validator
        correct = Collaboration::ExternalBenchmarks.validate_answer(benchmark, result, {})

        results[:total] += 1
        results[:by_source][source_name][:total] += 1

        if correct
          results[:correct] += 1
          results[:by_source][source_name][:correct] += 1
          puts "   ✓ Correct (#{result[:execution_time_ms]}ms)"
        else
          puts "   ✗ Wrong"
          puts "     Expected: #{benchmark[:answer]}"
          puts "     Got: #{result[:answer]&.truncate(50)}"
        end
      rescue => e
        puts "   ✗ Error: #{e.message}"
        results[:total] += 1
        results[:by_source][source_name][:total] += 1
      end

      puts ""
    end

    puts "=" * 60
    puts "📊 RESULTS"
    puts "=" * 60
    puts "Overall: #{results[:correct]}/#{results[:total]} (#{(results[:correct].to_f / results[:total] * 100).round(1)}%)"
    puts ""
    puts "By Source:"
    results[:by_source].each do |src, stats|
      acc = stats[:total] > 0 ? (stats[:correct].to_f / stats[:total] * 100).round(1) : 0
      puts "  #{src}: #{stats[:correct]}/#{stats[:total]} (#{acc}%)"
    end
    puts "=" * 60
  end

  desc "Run quick external benchmark (one from each source)"
  task :external_quick, [:use_scout] => :environment do |t, args|
    entity = Entity.first
    user = User.first

    unless entity && user
      puts "❌ No entity or user found"
      next
    end

    benchmarks = Collaboration::ExternalBenchmarks.quick_test_set

    puts "\n" + "=" * 60
    puts "⚡ QUICK EXTERNAL BENCHMARK"
    puts "=" * 60
    puts "Using: Scout (main chat interface)"
    puts "Tasks: #{benchmarks.size} (one per source)"
    puts ""

    # Use Scout directly via SystemBenchmarkRunner
    runner = Collaboration::SystemBenchmarkRunner.new(entity: entity, user: user)
    correct = 0

    benchmarks.each_with_index do |benchmark, i|
      puts "#{i + 1}. [#{benchmark[:source]}] #{benchmark[:question].truncate(50)}"

      begin
        # Execute prompt through Scout
        response = runner.send(:execute_prompt, benchmark[:question], timeout: 60)

        if response[:error]
          puts "   ✗ Error: #{response[:error]}"
          next
        end

        # Validate the answer
        passed = Collaboration::ExternalBenchmarks.validate_answer(benchmark, response, {})

        if passed
          correct += 1
          puts "   ✓ Correct"
        else
          puts "   ✗ Wrong (expected: #{benchmark[:answer].to_s.truncate(30)})"
          puts "     Got: #{response[:answer].to_s.truncate(50)}"
        end
      rescue => e
        puts "   ✗ Error: #{e.message}"
      end
    end

    puts ""
    puts "Result: #{correct}/#{benchmarks.size} (#{(correct.to_f / benchmarks.size * 100).round(1)}%)"
    puts "=" * 60
  end

  desc "Run FULL external benchmark suite (all 25 tests) with honest comparison"
  task :full_comparison => :environment do |t, args|
    # REAL baseline scores from public leaderboards (2024-2025)
    # Sources: 
    # - SimpleQA: https://openai.com/index/introducing-simpleqa/
    # - MMLU: https://paperswithcode.com/sota/multi-task-language-understanding-on-mmlu
    # - GAIA: https://huggingface.co/spaces/gaia-benchmark/leaderboard
    baselines = {
      'Claude 3.5 Sonnet' => { simpleqa: 28.4, mmlu: 88.7, gaia: 53.0, bfcl: 90.0 },
      'Claude 3 Opus' => { simpleqa: 23.0, mmlu: 86.8, gaia: 42.0, bfcl: 85.0 },
      'GPT-4o' => { simpleqa: 38.2, mmlu: 88.7, gaia: 49.0, bfcl: 88.0 },
      'GPT-4 Turbo' => { simpleqa: 24.2, mmlu: 86.4, gaia: 45.0, bfcl: 85.0 },
      'o1-preview' => { simpleqa: 42.7, mmlu: 90.8, gaia: 72.0, bfcl: 'N/A' }
    }

    entity = Entity.first
    user = User.first

    unless entity && user
      puts "❌ No entity or user found"
      next
    end

    puts "\n" + "=" * 70
    puts "🔬 AMOS FULL BENCHMARK - HONEST COMPARISON"
    puts "=" * 70
    puts "Running ALL #{Collaboration::ExternalBenchmarks.total_count} external benchmark tests..."
    puts "Model: Claude Sonnet 4.5 (via Bedrock)"
    puts ""
    puts "⚠️  IMPORTANT CAVEATS:"
    puts "  - Our sample size is SMALL (#{Collaboration::ExternalBenchmarks.total_count} tests)"
    puts "  - Real benchmarks use 1000s of questions"
    puts "  - AMOS adds tool overhead that raw models don't have"
    puts "  - We're testing the FULL SYSTEM, not just the LLM"
    puts "=" * 70
    puts ""

    runner = Collaboration::SystemBenchmarkRunner.new(entity: entity, user: user)
    amos_scores = {}
    all_results = []
    total_time = 0

    # Run ALL benchmarks by category
    Collaboration::ExternalBenchmarks.all_benchmarks.each do |category, benchmarks|
      puts "📦 #{category.to_s.upcase} (#{benchmarks.size} tests)"
      correct = 0
      category_time = 0
      
      benchmarks.each_with_index do |b, i|
        start = Time.current
        response = runner.send(:execute_prompt, b[:question], timeout: 90)
        elapsed = Time.current - start
        category_time += elapsed
        
        passed = !response[:error] && Collaboration::ExternalBenchmarks.validate_answer(b, response, {})
        correct += 1 if passed
        
        all_results << {
          category: category,
          id: b[:id],
          question: b[:question].truncate(50),
          expected: b[:answer].to_s.truncate(30),
          got: response[:answer].to_s.truncate(30),
          passed: passed,
          time_ms: (elapsed * 1000).round,
          error: response[:error]
        }
        
        print passed ? '.' : 'x'
      end
      
      amos_scores[category] = {
        correct: correct,
        total: benchmarks.size,
        pct: (correct.to_f / benchmarks.size * 100).round(1),
        avg_time_ms: (category_time / benchmarks.size * 1000).round
      }
      total_time += category_time
      
      puts " #{correct}/#{benchmarks.size} (#{amos_scores[category][:pct]}%) - avg #{amos_scores[category][:avg_time_ms]}ms"
    end

    # Calculate overall
    total_correct = amos_scores.values.sum { |s| s[:correct] }
    total_tests = amos_scores.values.sum { |s| s[:total] }
    overall_pct = (total_correct.to_f / total_tests * 100).round(1)

    puts ""
    puts "=" * 70
    puts "📊 RESULTS SUMMARY"
    puts "=" * 70
    puts ""
    puts "AMOS Overall: #{total_correct}/#{total_tests} (#{overall_pct}%)"
    puts "Total Time: #{total_time.round(1)}s"
    puts ""
    
    puts "By Category:"
    puts "| Category | AMOS | Baseline (Sonnet 3.5) | Delta |"
    puts "|----------|------|----------------------|-------|"
    
    category_baselines = {
      gaia: baselines['Claude 3.5 Sonnet'][:gaia],
      bfcl: baselines['Claude 3.5 Sonnet'][:bfcl],
      toolbench: 85.0,  # Estimated
      simpleqa: baselines['Claude 3.5 Sonnet'][:simpleqa],
      mmlu: baselines['Claude 3.5 Sonnet'][:mmlu],
      code: 80.0  # Estimated for simple code tasks
    }
    
    amos_scores.each do |cat, scores|
      baseline = category_baselines[cat] || 'N/A'
      delta = baseline.is_a?(Numeric) ? (scores[:pct] - baseline).round(1) : 'N/A'
      delta_str = delta.is_a?(Numeric) ? (delta >= 0 ? "+#{delta}" : delta.to_s) : delta
      puts "| #{cat.to_s.ljust(10)} | #{scores[:pct]}% | #{baseline}% | #{delta_str} |"
    end

    puts ""
    puts "=" * 70
    puts "🏆 COMPARISON TO RAW MODELS"
    puts "=" * 70
    puts ""
    puts "| Model | SimpleQA | MMLU | GAIA | BFCL |"
    puts "|-------|----------|------|------|------|"
    
    baselines.each do |model, scores|
      puts "| #{model.ljust(17)} | #{scores[:simpleqa]}% | #{scores[:mmlu]}% | #{scores[:gaia]}% | #{scores[:bfcl]} |"
    end
    
    # Map our categories to standard benchmarks
    amos_simpleqa = amos_scores[:simpleqa]&.dig(:pct) || 'N/A'
    amos_mmlu = amos_scores[:mmlu]&.dig(:pct) || 'N/A'
    amos_gaia = amos_scores[:gaia]&.dig(:pct) || 'N/A'
    amos_bfcl = amos_scores[:bfcl]&.dig(:pct) || 'N/A'
    
    puts "| **AMOS (Scout)**  | #{amos_simpleqa}% | #{amos_mmlu}% | #{amos_gaia}% | #{amos_bfcl}% |"
    
    puts ""
    puts "=" * 70
    puts "🔍 HONEST ANALYSIS"
    puts "=" * 70
    puts ""
    
    # Honest analysis
    if overall_pct >= 90
      puts "✅ EXCELLENT: #{overall_pct}% overall accuracy"
      puts "   But remember: small sample size may not reflect real-world performance"
    elsif overall_pct >= 70
      puts "✓ GOOD: #{overall_pct}% overall accuracy"
      puts "   Competitive with baseline models on these specific tests"
    elsif overall_pct >= 50
      puts "⚠️ MODERATE: #{overall_pct}% overall accuracy"
      puts "   Room for improvement - investigate failed categories"
    else
      puts "❌ NEEDS WORK: #{overall_pct}% overall accuracy"
      puts "   Significant issues to address"
    end
    
    puts ""
    puts "Failed tests:"
    failed = all_results.select { |r| !r[:passed] }
    if failed.empty?
      puts "  None! 🎉"
    else
      failed.each do |f|
        puts "  ✗ [#{f[:category]}] #{f[:id]}: #{f[:question]}"
        puts "    Expected: #{f[:expected]}"
        puts "    Got: #{f[:got] || f[:error]}"
      end
    end
    
    puts ""
    puts "=" * 70
    puts "⚠️  REMEMBER: This is a SMALL SAMPLE benchmark."
    puts "Real benchmarks use thousands of diverse questions."
    puts "These results are indicative, not definitive."
    puts "=" * 70
  end

  # ============================================
  # AGENT COLLABORATION BENCHMARKS (existing)
  # ============================================

  desc "Run GSM8K math benchmarks on an agent"
  task :gsm8k, [:agent_slug] => :environment do |t, args|
    agent_slug = args[:agent_slug] || 'scout'
    run_benchmark_category(:gsm8k, agent_slug)
  end

  desc "Run HotpotQA-style benchmarks on an agent"
  task :hotpot, [:agent_slug] => :environment do |t, args|
    agent_slug = args[:agent_slug] || 'web_research_specialist'
    run_benchmark_category(:hotpot, agent_slug)
  end

  desc "Run tool use benchmarks on an agent"
  task :tool_use, [:agent_slug] => :environment do |t, args|
    agent_slug = args[:agent_slug] || 'weather_scout'
    run_benchmark_category(:tool_use, agent_slug)
  end

  desc "Run collaboration benchmarks"
  task :collaboration, [:agent_slug] => :environment do |t, args|
    agent_slug = args[:agent_slug] || 'scout'
    run_benchmark_category(:collaboration, agent_slug)
  end

  desc "Run A/B comparison: collaboration ON vs OFF"
  task :ab_compare, [:agent_slug] => :environment do |t, args|
    agent_slug = args[:agent_slug] || 'weather_scout'
    
    entity = Entity.first
    user = User.first
    
    puts "\n=== A/B Comparison: #{agent_slug} ==="
    puts "Testing with collaboration ENABLED vs DISABLED"
    puts ""
    
    runner = Collaboration::BenchmarkRunner.new(entity: entity, user: user)
    results = runner.run_ab_comparison(agent_slug: agent_slug)
    
    if results[:error]
      puts "Error: #{results[:error]}"
      return
    end
    
    puts "WITHOUT Collaboration:"
    puts "  Accuracy: #{results[:without_collaboration][:accuracy]}%"
    puts "  Avg execution time: #{results[:without_collaboration][:avg_execution_time_ms]}ms"
    puts ""
    puts "WITH Collaboration:"
    puts "  Accuracy: #{results[:with_collaboration][:accuracy]}%"
    puts "  Asked for help: #{results[:with_collaboration][:asked_for_help_count]} times"
    puts "  Avg execution time: #{results[:with_collaboration][:avg_execution_time_ms]}ms"
    puts ""
    puts "Comparison:"
    puts "  Improvement: #{results[:comparison][:improvement_percentage_points]} percentage points"
    puts "  Collaboration helped: #{results[:comparison][:collaboration_helped]}"
    puts "  Tasks where collab helped: #{results[:comparison][:tasks_where_collab_helped]}"
    puts "  Tasks where collab hurt: #{results[:comparison][:tasks_where_collab_hurt]}"
  end

  desc "Run cross-domain test (specialists vs non-specialists)"
  task cross_domain: :environment do
    entity = Entity.first
    user = User.first
    
    puts "\n=== Cross-Domain Test ==="
    puts "Testing if non-specialists correctly delegate to specialists"
    puts ""
    
    runner = Collaboration::BenchmarkRunner.new(entity: entity, user: user)
    results = runner.run_cross_domain_test
    
    puts "Summary:"
    puts "  Total tests: #{results[:summary][:total_tests]}"
    puts "  Specialist success rate: #{results[:summary][:specialist_success_rate]}%"
    puts "  Non-specialist (solo) success rate: #{results[:summary][:non_specialist_solo_success_rate]}%"
    puts "  Non-specialist (with collab) success rate: #{results[:summary][:non_specialist_collab_success_rate]}%"
    puts "  Times collaboration helped: #{results[:summary][:collaboration_helped_count]}"
    puts ""
    
    puts "Detailed Results:"
    results[:tests].each do |test|
      puts ""
      puts "  Task: #{test[:task_id]} (#{test[:category]})"
      puts "    Specialist (#{test[:specialist][:agent]}): #{test[:specialist][:correct] ? '✓' : '✗'}"
      puts "    Non-specialist solo (#{test[:non_specialist_solo][:agent]}): #{test[:non_specialist_solo][:correct] ? '✓' : '✗'}"
      puts "    Non-specialist + help: #{test[:non_specialist_with_help][:correct] ? '✓' : '✗'}"
      puts "    Asked for help: #{test[:non_specialist_with_help][:asked_for_help]}"
      puts "    Helper used: #{test[:non_specialist_with_help][:helper_used] || 'none'}"
      puts "    Collaboration helped: #{test[:collaboration_helped] ? 'YES' : 'no'}"
    end
  end

  desc "Run quick validation (3 easy tasks)"
  task quick: :environment do
    entity = Entity.first
    user = User.first
    agent = AgentPlugin.find_by(slug: 'scout', entity: entity) || AgentPlugin.active.where(entity: entity).first
    
    puts "\n=== Quick Validation ==="
    puts "Agent: #{agent&.name || 'None found'}"
    puts ""
    
    unless agent
      puts "No agent found!"
      return
    end
    
    benchmarks = Collaboration::PublicBenchmarks.get_by_difficulty('easy').first(3)
    runner = Collaboration::BenchmarkRunner.new(entity: entity, user: user)
    
    correct = 0
    benchmarks.each_with_index do |benchmark, i|
      puts "Task #{i + 1}: #{benchmark[:question].truncate(60)}"
      
      result = runner.run_single_benchmark(
        agent_slug: agent.slug,
        task_id: benchmark[:id],
        allow_collaboration: true
      )
      
      if result[:error]
        puts "  Error: #{result[:error]}"
      else
        puts "  Answer: #{result[:answer]&.truncate(50) || 'No answer'}"
        puts "  Expected: #{benchmark[:answer]}"
        puts "  Correct: #{result[:correct] ? '✓ YES' : '✗ NO'}"
        puts "  Time: #{result[:execution_time_ms]}ms"
        correct += 1 if result[:correct]
      end
      puts ""
    end
    
    puts "Results: #{correct}/#{benchmarks.size} correct (#{(correct.to_f / benchmarks.size * 100).round(1)}%)"
  end

  desc "Run full benchmark suite"
  task :full, [:agent_slug] => :environment do |t, args|
    agent_slug = args[:agent_slug]
    
    entity = Entity.first
    user = User.first
    
    puts "\n=== Full Benchmark Suite ==="
    puts "Agent: #{agent_slug || 'all active agents'}"
    puts "Started at: #{Time.current}"
    puts ""
    
    all_results = {
      started_at: Time.current,
      results_by_category: {},
      summary: {}
    }
    
    [:gsm8k, :hotpot, :tool_use].each do |category|
      puts "Running #{category} benchmarks..."
      benchmarks = Collaboration::PublicBenchmarks.get_benchmark(category)
      
      runner = Collaboration::BenchmarkRunner.new(entity: entity, user: user)
      
      # Use specified agent or pick appropriate one
      test_agent = if agent_slug
        AgentPlugin.find_by(slug: agent_slug, entity: entity)
      else
        pick_agent_for_category(category, entity)
      end
      
      next unless test_agent
      
      category_results = []
      benchmarks.each do |benchmark|
        result = runner.run_single_benchmark(
          agent_slug: test_agent.slug,
          task_id: benchmark[:id],
          allow_collaboration: true
        )
        category_results << result
        print result[:correct] ? '.' : 'x'
      end
      puts ""
      
      correct = category_results.count { |r| r[:correct] }
      all_results[:results_by_category][category] = {
        agent: test_agent.slug,
        total: category_results.size,
        correct: correct,
        accuracy: (correct.to_f / category_results.size * 100).round(1),
        avg_time_ms: (category_results.sum { |r| r[:execution_time_ms] || 0 } / category_results.size).round
      }
    end
    
    puts ""
    puts "=== Results Summary ==="
    all_results[:results_by_category].each do |category, results|
      puts "#{category}:"
      puts "  Agent: #{results[:agent]}"
      puts "  Accuracy: #{results[:correct]}/#{results[:total]} (#{results[:accuracy]}%)"
      puts "  Avg time: #{results[:avg_time_ms]}ms"
      puts ""
    end
    
    total_correct = all_results[:results_by_category].values.sum { |r| r[:correct] }
    total_tasks = all_results[:results_by_category].values.sum { |r| r[:total] }
    
    puts "Overall: #{total_correct}/#{total_tasks} (#{(total_correct.to_f / total_tasks * 100).round(1)}%)"
    puts "Completed at: #{Time.current}"
  end

  desc "Test energy economics impact"
  task energy_test: :environment do
    entity = Entity.first
    user = User.first
    
    puts "\n=== Energy Economics Test ==="
    
    # Pick an agent
    agent = AgentPlugin.find_by(slug: 'weather_scout', entity: entity)
    unless agent
      puts "Weather Scout not found"
      return
    end
    
    # Reset energy
    agent.energy_state&.update!(current_energy: 75.0, tasks_completed: 0, tasks_failed: 0)
    
    puts "Agent: #{agent.name}"
    puts "Starting energy: #{agent.current_energy}"
    puts ""
    
    runner = Collaboration::BenchmarkRunner.new(entity: entity, user: user)
    
    # Run 5 tasks and track energy
    5.times do |i|
      benchmark = Collaboration::PublicBenchmarks.get_by_difficulty('easy').sample
      
      puts "Task #{i + 1}: #{benchmark[:question].truncate(50)}"
      energy_before = agent.reload.current_energy
      
      result = runner.run_single_benchmark(
        agent_slug: agent.slug,
        task_id: benchmark[:id],
        allow_collaboration: true
      )
      
      energy_after = agent.reload.current_energy
      energy_change = energy_after - energy_before
      
      puts "  Result: #{result[:correct] ? 'Correct' : 'Wrong'}"
      puts "  Energy: #{energy_before.round(1)} → #{energy_after.round(1)} (#{energy_change >= 0 ? '+' : ''}#{energy_change.round(1)})"
      puts ""
    end
    
    puts "Final energy: #{agent.reload.current_energy.round(1)}"
    puts "Tasks completed: #{agent.energy_state.tasks_completed}"
    puts "Tasks failed: #{agent.energy_state.tasks_failed}"
    puts "In school: #{agent.in_school?}"
  end

  private

  def run_benchmark_category(category, agent_slug)
    entity = Entity.first
    user = User.first
    
    agent = AgentPlugin.find_by(slug: agent_slug, entity: entity)
    unless agent
      puts "Agent '#{agent_slug}' not found"
      return
    end
    
    benchmarks = Collaboration::PublicBenchmarks.get_benchmark(category)
    
    puts "\n=== #{category.to_s.upcase} Benchmarks ==="
    puts "Agent: #{agent.name}"
    puts "Tasks: #{benchmarks.size}"
    puts ""
    
    runner = Collaboration::BenchmarkRunner.new(entity: entity, user: user)
    
    correct = 0
    total_time = 0
    
    benchmarks.each_with_index do |benchmark, i|
      puts "#{i + 1}. #{benchmark[:question].truncate(70)}"
      
      result = runner.run_single_benchmark(
        agent_slug: agent_slug,
        task_id: benchmark[:id],
        allow_collaboration: true
      )
      
      if result[:error]
        puts "   Error: #{result[:error]}"
      else
        status = result[:correct] ? '✓' : '✗'
        puts "   #{status} Answer: #{result[:answer]&.truncate(40) || 'none'}"
        puts "     Expected: #{benchmark[:answer]}"
        puts "     Time: #{result[:execution_time_ms]}ms | Collab: #{result[:asked_for_help] ? 'yes' : 'no'}"
        correct += 1 if result[:correct]
        total_time += result[:execution_time_ms] || 0
      end
      puts ""
    end
    
    puts "=== Results ==="
    puts "Correct: #{correct}/#{benchmarks.size} (#{(correct.to_f / benchmarks.size * 100).round(1)}%)"
    puts "Avg time: #{(total_time / benchmarks.size).round}ms"
  end

  def pick_agent_for_category(category, entity)
    case category
    when :gsm8k
      AgentPlugin.find_by(slug: 'scout', entity: entity) ||
        AgentPlugin.active.where(entity: entity).first
    when :hotpot
      AgentPlugin.find_by(slug: 'web_research_specialist', entity: entity) ||
        AgentPlugin.active.where(entity: entity).first
    when :tool_use
      AgentPlugin.find_by(slug: 'weather_scout', entity: entity) ||
        AgentPlugin.active.where(entity: entity).first
    else
      AgentPlugin.active.where(entity: entity).first
    end
  end

  # ============================================
  # REPORTING TASKS
  # ============================================

  desc "Generate benchmark report (JSON)"
  task :report, [:days] => :environment do |t, args|
    days = (args[:days] || 30).to_i
    entity = Entity.first
    
    puts "\n=== Generating Benchmark Report ==="
    puts "Period: Last #{days} days"
    puts ""
    
    json = Collaboration::BenchmarkTracker.export_to_json(entity: entity, days: days)
    
    # Save to file
    filename = "benchmark_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
    filepath = Rails.root.join('tmp', filename)
    File.write(filepath, json)
    
    puts "Report saved to: #{filepath}"
    puts ""
    
    # Print summary
    report = JSON.parse(json)
    puts "Summary:"
    puts "  Total runs: #{report['summary']['total_runs']}"
    puts "  Total tasks: #{report['summary']['total_tasks']}"
    puts "  Overall accuracy: #{report['summary']['overall_accuracy']}%"
    puts "  Collaboration rate: #{report['summary']['collaboration_rate']}%"
  end

  desc "Generate markdown benchmark report"
  task :report_md, [:days] => :environment do |t, args|
    days = (args[:days] || 30).to_i
    entity = Entity.first
    
    puts "\n=== Generating Markdown Report ==="
    
    markdown = Collaboration::BenchmarkTracker.export_to_markdown(entity: entity, days: days)
    
    # Save to file
    filename = "BENCHMARK_REPORT.md"
    filepath = Rails.root.join('docs', filename)
    File.write(filepath, markdown)
    
    puts "Report saved to: #{filepath}"
    puts ""
    puts markdown
  end

  desc "Show benchmark history"
  task history: :environment do
    entity = Entity.first
    runs = BenchmarkRun.where(entity: entity).completed.recent(20)
    
    puts "\n=== Benchmark History ==="
    puts ""
    
    if runs.empty?
      puts "No benchmark runs found."
      return
    end
    
    puts "| Date | Type | Category | Agent | Tasks | Accuracy | Collab Rate |"
    puts "|------|------|----------|-------|-------|----------|-------------|"
    
    runs.each do |run|
      puts "| #{run.created_at.strftime('%Y-%m-%d %H:%M')} | #{run.run_type} | #{run.benchmark_category || '-'} | #{run.agent_slug || '-'} | #{run.total_tasks} | #{run.accuracy_percentage}% | #{run.collaboration_rate}% |"
    end
    
    puts ""
    puts "Total runs: #{runs.count}"
  end

  desc "Compare collaboration ON vs OFF over time"
  task compare_history: :environment do
    entity = Entity.first
    
    with_collab = BenchmarkRun.where(entity: entity).completed.with_collaboration
    without_collab = BenchmarkRun.where(entity: entity).completed.without_collaboration
    
    puts "\n=== Collaboration Comparison ==="
    puts ""
    
    puts "WITH Collaboration:"
    puts "  Runs: #{with_collab.count}"
    puts "  Avg Accuracy: #{Collaboration::BenchmarkTracker.send(:weighted_accuracy, with_collab)}%"
    puts "  Avg Collab Rate: #{(with_collab.average(:collaboration_requests).to_f / (with_collab.average(:total_tasks) || 1) * 100).round(1)}%"
    puts ""
    
    puts "WITHOUT Collaboration:"
    puts "  Runs: #{without_collab.count}"
    puts "  Avg Accuracy: #{Collaboration::BenchmarkTracker.send(:weighted_accuracy, without_collab)}%"
    puts ""
    
    improvement = Collaboration::BenchmarkTracker.send(:improvement_from_collaboration, with_collab, without_collab)
    puts "Improvement from Collaboration:"
    puts "  Percentage Points: #{improvement[:percentage_points]}"
    puts "  Relative: #{improvement[:relative_improvement]}%"
  end

  desc "Run tracked benchmark (results saved to DB)"
  task :tracked, [:agent_slug, :category] => :environment do |t, args|
    agent_slug = args[:agent_slug] || 'scout'
    category = (args[:category] || 'gsm8k').to_sym
    
    entity = Entity.first
    user = User.first
    
    agent = AgentPlugin.find_by(slug: agent_slug, entity: entity)
    unless agent
      puts "Agent '#{agent_slug}' not found"
      return
    end
    
    benchmarks = Collaboration::PublicBenchmarks.get_benchmark(category)
    
    puts "\n=== Tracked Benchmark Run ==="
    puts "Agent: #{agent.name}"
    puts "Category: #{category}"
    puts "Tasks: #{benchmarks.size}"
    puts ""
    
    # Start tracked run
    tracker = Collaboration::BenchmarkTracker.new(entity: entity)
    run = tracker.start_run(
      run_type: 'category',
      category: category.to_s,
      agent_slug: agent_slug,
      collaboration_enabled: true
    )
    
    runner = Collaboration::BenchmarkRunner.new(entity: entity, user: user)
    
    correct = 0
    total_time = 0
    total_tokens = 0
    
    benchmarks.each_with_index do |benchmark, i|
      print "Task #{i + 1}/#{benchmarks.size}: "
      
      result = runner.run_single_benchmark(
        agent_slug: agent_slug,
        task_id: benchmark[:id],
        allow_collaboration: true
      )
      
      # Record to tracker
      tracker.record_task_result(
        task_id: benchmark[:id],
        category: category.to_s,
        difficulty: benchmark[:difficulty],
        answer: result[:answer],
        correct: result[:correct],
        execution_time_ms: result[:execution_time_ms],
        tokens_used: result[:tokens_used] || 0,
        asked_for_help: result[:asked_for_help],
        helper_used: result[:helper_used],
        collaboration_helped: result[:asked_for_help] && result[:correct]
      )
      
      print result[:correct] ? '✓' : '✗'
      puts " (#{result[:execution_time_ms]}ms)"
      
      correct += 1 if result[:correct]
      total_time += result[:execution_time_ms] || 0
      total_tokens += result[:tokens_used] || 0
    end
    
    # Complete run
    tracker.complete_run(
      total_tasks: benchmarks.size,
      correct_count: correct,
      accuracy_percentage: (correct.to_f / benchmarks.size * 100).round(1),
      avg_execution_time_ms: (total_time / benchmarks.size).round,
      total_tokens_used: total_tokens
    )
    
    puts ""
    puts "=== Results ==="
    puts "Run ID: #{run.run_id}"
    puts "Correct: #{correct}/#{benchmarks.size} (#{run.accuracy_percentage}%)"
    puts "Avg time: #{run.avg_execution_time_ms}ms"
    puts "Collaboration rate: #{run.collaboration_rate}%"
    puts ""
    puts "Results saved to database. Run 'rake benchmark:report' to generate a report."
  end
end

