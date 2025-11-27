# frozen_string_literal: true

namespace :benchmark do
  namespace :real do
    desc "Show available real benchmark datasets"
    task datasets: :environment do
      puts "\n" + "=" * 70
      puts "📚 AVAILABLE BENCHMARK DATASETS"
      puts "=" * 70
      puts ""
      
      Benchmarks::HuggingfaceDatasets.available.each do |dataset|
        cached = dataset[:cached] ? "✓ cached" : "⬇ needs download"
        puts "#{dataset[:key].to_s.ljust(12)} | #{dataset[:sample_size].to_s.rjust(4)} samples | #{cached}"
        puts "  #{dataset[:description]}"
        puts ""
      end
      
      puts "=" * 70
      puts "Use 'rake benchmark:real:download[dataset]' to download a dataset"
      puts "Use 'rake benchmark:real:run[dataset,count]' to run a benchmark"
      puts "=" * 70
    end

    desc "Download a benchmark dataset from HuggingFace"
    task :download, [:dataset] => :environment do |t, args|
      dataset = args[:dataset]&.to_sym
      
      unless dataset
        puts "Usage: rake benchmark:real:download[dataset]"
        puts "Available: #{Benchmarks::HuggingfaceDatasets::DATASETS.keys.join(', ')}"
        next
      end

      puts "Downloading #{dataset} from HuggingFace..."
      
      begin
        data = Benchmarks::HuggingfaceDatasets.download(dataset, force: true)
        puts "✅ Downloaded #{data.size} questions"
        puts "Sample question: #{data.first[:question].truncate(80)}"
      rescue => e
        puts "❌ Error: #{e.message}"
      end
    end

    # ============================================
    # COMPARATIVE BENCHMARKS
    # ============================================

    desc "Compare Raw LLM vs AMOS vs AMOS+Collaboration"
    task :compare, [:sample_size] => :environment do |t, args|
      sample_size = (args[:sample_size] || 5).to_i
      
      entity = Entity.first
      user = User.first
      
      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      benchmark = Benchmarks::ComparativeBenchmark.new(entity: entity, user: user)
      benchmark.run_comparison(sample_size: sample_size)
    end

    desc "Run A/B test: Collaboration vs No Collaboration"
    task :ab_collab, [:sample_size] => :environment do |t, args|
      sample_size = (args[:sample_size] || 20).to_i
      
      entity = Entity.first
      user = User.first
      
      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      benchmark = Benchmarks::ComparativeBenchmark.new(entity: entity, user: user)
      benchmark.run_collaboration_ab_test(sample_size: sample_size)
    end

    desc "Quick comparison (3 per category)"
    task compare_quick: :environment do
      Rake::Task['benchmark:real:compare'].invoke(3)
    end

    desc "Full comparison (10 per category)"  
    task compare_full: :environment do
      Rake::Task['benchmark:real:compare'].invoke(10)
    end

    desc "Compare Raw Claude vs AMOS on HuggingFace benchmarks"
    task :compare_hf, [:dataset, :count] => :environment do |t, args|
      dataset = (args[:dataset] || 'gsm8k').to_sym
      count = (args[:count] || 20).to_i
      
      entity = Entity.first
      user = User.first
      
      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      puts "\n" + "=" * 70
      puts "🔬 RAW CLAUDE vs AMOS on #{dataset.to_s.upcase}"
      puts "=" * 70
      puts "Testing if AMOS adds value over raw Claude Sonnet 4.5"
      puts "Dataset: #{dataset}, Sample: #{count} questions"
      puts "=" * 70
      puts ""

      # Load questions
      questions = Benchmarks::HuggingfaceDatasets.get_questions(dataset, limit: count)
      
      if questions.empty?
        puts "❌ No questions loaded. Run: rake benchmark:real:download[#{dataset}]"
        next
      end

      # Phase 1: Raw Claude (no tools)
      puts "📊 Phase 1: RAW CLAUDE (no tools)"
      puts "-" * 50
      ai_service = BedrockService.new(user: user, entity: entity)
      raw_correct = 0
      raw_times = []
      
      questions.each_with_index do |q, idx|
        print "  #{idx + 1}/#{count}: "
        start = Time.current
        
        begin
          response = ai_service.send_message(
            "You are a helpful assistant. Answer concisely. For multiple choice, respond with just the letter (A, B, C, or D).",
            [{ role: "user", content: q[:question] }],
            max_tokens: 500,
            temperature: 0.1
          )
          answer = response.is_a?(Hash) ? (response[:content] || response['content'] || response.to_s) : response.to_s
          
          # Check if correct
          expected = q[:answer].to_s.strip
          actual = answer.to_s.strip
          
          # For multiple choice, check if the letter matches
          correct = actual.upcase.start_with?(expected.upcase) || 
                    actual.include?(expected) ||
                    expected.include?(actual.split.first.to_s)
          
          raw_correct += 1 if correct
          raw_times << (Time.current - start)
          print correct ? '.' : 'x'
        rescue => e
          print 'E'
        end
      end
      puts ""
      raw_pct = (raw_correct.to_f / count * 100).round(1)
      raw_avg_time = (raw_times.sum / raw_times.size * 1000).round if raw_times.any?
      puts "Result: #{raw_correct}/#{count} (#{raw_pct}%) - Avg: #{raw_avg_time}ms"
      puts ""

      # Phase 2: AMOS (Scout with tools)
      puts "📊 Phase 2: AMOS (Scout with tools)"
      puts "-" * 50
      amos_correct = 0
      amos_times = []
      
      questions.each_with_index do |q, idx|
        print "  #{idx + 1}/#{count}: "
        start = Time.current
        
        begin
          session_id = "benchmark_#{SecureRandom.hex(4)}"
          scout = ScoutGenericToolsServiceV2.new(user, entity, session_id)
          
          response_text = ""
          callback = ->(chunk) { response_text += chunk.to_s if chunk.is_a?(String) }
          
          result = scout.process_message_with_tools_streaming(
            "Answer concisely. For multiple choice, respond with just the letter. Question: #{q[:question]}",
            callback,
            [],
            nil
          )
          
          answer = if result.is_a?(Hash)
            final = result[:final_response] || result['final_response'] || {}
            final[:message] || final['message'] || result[:message] || response_text
          else
            result.to_s.presence || response_text
          end
          
          # Check if correct
          expected = q[:answer].to_s.strip
          actual = answer.to_s.strip
          
          correct = actual.upcase.start_with?(expected.upcase) || 
                    actual.include?(expected) ||
                    expected.include?(actual.split.first.to_s)
          
          amos_correct += 1 if correct
          amos_times << (Time.current - start)
          print correct ? '.' : 'x'
        rescue => e
          print 'E'
        end
        
        sleep(0.2) # Rate limiting
      end
      puts ""
      amos_pct = (amos_correct.to_f / count * 100).round(1)
      amos_avg_time = (amos_times.sum / amos_times.size * 1000).round if amos_times.any?
      puts "Result: #{amos_correct}/#{count} (#{amos_pct}%) - Avg: #{amos_avg_time}ms"
      puts ""

      # Summary
      delta = amos_pct - raw_pct
      puts "=" * 70
      puts "📊 COMPARISON RESULTS"
      puts "=" * 70
      puts ""
      puts "| System | Correct | Accuracy | Avg Time |"
      puts "|--------|---------|----------|----------|"
      puts "| Raw Claude | #{raw_correct}/#{count} | #{raw_pct}% | #{raw_avg_time}ms |"
      puts "| AMOS (Scout) | #{amos_correct}/#{count} | #{amos_pct}% | #{amos_avg_time}ms |"
      puts "| Delta | #{amos_correct - raw_correct} | #{delta >= 0 ? '+' : ''}#{delta}% | #{amos_avg_time.to_i - raw_avg_time.to_i}ms |"
      puts ""
      
      if delta > 2
        puts "✅ AMOS HELPS: +#{delta}% improvement"
      elsif delta >= -2
        puts "⚠️ COMPARABLE: #{delta}% difference (within margin)"
      else
        puts "❌ AMOS SLOWER: #{delta}% (overhead without benefit)"
      end
      puts "=" * 70
    end

    # ============================================
    # DATASET MANAGEMENT
    # ============================================

  # ============================================
  # BUSINESS OPERATIONS BENCHMARK (BOB)
  # "MMLU for Running a Business"
  # ============================================
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
      puts "  rake benchmark:business:export    # Export results for manual scoring"
      puts "=" * 70
    end

    desc "Run quick Business Benchmark (2 per category)"
    task :quick => :environment do
      entity = Entity.first
      user = User.first
      
      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      runner = Benchmarks::BusinessBenchmarkRunner.new(entity: entity, user: user)
      runner.run_quick_benchmark(tasks_per_category: 2)
    end

    desc "Run full Business Benchmark (all 100 tasks)"
    task :full => :environment do
      entity = Entity.first
      user = User.first
      
      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      runner = Benchmarks::BusinessBenchmarkRunner.new(entity: entity, user: user)
      runner.run_full_benchmark
    end

    desc "Compare Raw Claude vs AMOS on Business Benchmark"
    task :compare, [:tasks_per_category] => :environment do |t, args|
      tasks_per_category = (args[:tasks_per_category] || 1).to_i
      
      entity = Entity.first
      user = User.first
      
      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      runner = Benchmarks::BusinessBenchmarkRunner.new(entity: entity, user: user)
      runner.run_comparison(tasks_per_category: tasks_per_category)
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
        puts "Available tasks: #{Benchmarks::BusinessBenchmark.all_tasks.map { |t| t[:id] }.join(', ')}"
        next
      end

      entity = Entity.first
      user = User.first

      puts "\n" + "=" * 70
      puts "🏢 Running: #{task[:name]}"
      puts "=" * 70
      puts ""
      puts "Category: #{Benchmarks::BusinessBenchmark::CATEGORIES[task[:category]]}"
      puts "Difficulty: #{task[:difficulty]}"
      puts ""
      puts "Scenario:"
      puts task[:scenario]
      puts ""
      puts "Request:"
      puts task[:request]
      puts ""
      puts "Rubric:"
      task[:rubric].each { |r| puts "  • #{r}" }
      puts ""
      puts "-" * 70
      puts "Running with AMOS (Scout)..."
      puts "-" * 70

      runner = Benchmarks::BusinessBenchmarkRunner.new(entity: entity, user: user)
      result = runner.run_task(task, use_scout: true)

      puts ""
      puts "Response:"
      puts result[:response]
      puts ""
      puts "-" * 70
      puts "Time: #{result[:elapsed_ms]}ms"
      puts "=" * 70
    end

    desc "Run category-specific benchmark"
    task :category, [:category] => :environment do |t, args|
      category = args[:category]&.to_sym
      
      unless category && Benchmarks::BusinessBenchmark::CATEGORIES.key?(category)
        puts "Usage: rake benchmark:business:category[category]"
        puts "Available: #{Benchmarks::BusinessBenchmark::CATEGORIES.keys.join(', ')}"
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
      runner.run_tasks(tasks) do |idx, total, name|
        print "  #{idx}/#{total}: #{name.truncate(40)}... "
      end

      runner.generate_report
    end

    desc "Export benchmark results for manual scoring"
    task :export => :environment do
      # This would export the last run's results
      puts "Export functionality - run a benchmark first, then export"
    end
  end

  # ============================================
  # HUGGINGFACE DATASET MANAGEMENT
  # ============================================

    desc "Download all benchmark datasets"
    task download_all: :environment do
      Benchmarks::HuggingfaceDatasets::DATASETS.keys.each do |dataset|
        puts "\nDownloading #{dataset}..."
        begin
          data = Benchmarks::HuggingfaceDatasets.download(dataset, force: false)
          puts "  ✅ #{data.size} questions"
        rescue => e
          puts "  ❌ Error: #{e.message}"
        end
      end
    end

    desc "Run a real benchmark on a specific dataset"
    task :run, [:dataset, :count] => :environment do |t, args|
      dataset = args[:dataset]&.to_sym || :gsm8k
      count = (args[:count] || 50).to_i

      entity = Entity.first
      user = User.first

      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      puts "\n🔬 Running REAL benchmark: #{dataset}"
      puts "Sample size: #{count}"
      puts ""

      runner = Benchmarks::RealBenchmarkRunner.new(entity: entity, user: user)
      result = runner.run_dataset(dataset, sample_size: count)

      puts ""
      puts "=" * 70
      puts "RESULT: #{result[:correct]}/#{result[:total]} (#{result[:accuracy]}%)"
      puts "Average time: #{result[:avg_time_ms]}ms per question"
      puts "=" * 70
    end

    desc "Run full benchmark suite (multiple datasets)"
    task :full, [:sample_size] => :environment do |t, args|
      sample_size = (args[:sample_size] || 50).to_i

      entity = Entity.first
      user = User.first

      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      runner = Benchmarks::RealBenchmarkRunner.new(entity: entity, user: user)
      runner.run_full_suite(
        datasets: [:gsm8k, :simple_qa, :gaia],
        sample_size: sample_size
      )
    end

    desc "Run A/B comparison: with vs without collaboration"
    task :ab_test, [:dataset, :count] => :environment do |t, args|
      dataset = args[:dataset]&.to_sym || :gsm8k
      count = (args[:count] || 30).to_i

      entity = Entity.first
      user = User.first

      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      runner = Benchmarks::RealBenchmarkRunner.new(entity: entity, user: user)
      runner.run_ab_comparison(dataset, sample_size: count)
    end

    desc "Quick validation (10 questions from each dataset)"
    task quick: :environment do
      entity = Entity.first
      user = User.first

      unless entity && user
        puts "❌ No entity or user found"
        next
      end

      puts "\n⚡ QUICK BENCHMARK VALIDATION"
      puts "Running 10 questions from each dataset..."
      puts ""

      runner = Benchmarks::RealBenchmarkRunner.new(entity: entity, user: user)
      runner.run_full_suite(
        datasets: [:gsm8k, :simple_qa],
        sample_size: 10
      )
    end

    desc "Show benchmark history"
    task history: :environment do
      entity = Entity.first

      unless entity
        puts "❌ No entity found"
        next
      end

      runs = BenchmarkRun.where(entity: entity, run_type: 'real_benchmark')
                        .order(created_at: :desc)
                        .limit(20)

      if runs.empty?
        puts "No benchmark runs found. Run 'rake benchmark:real:full' to create one."
        next
      end

      puts "\n" + "=" * 70
      puts "📈 BENCHMARK HISTORY"
      puts "=" * 70
      puts ""
      puts "| Date | Questions | Accuracy | Datasets |"
      puts "|------|-----------|----------|----------|"

      runs.each do |run|
        datasets = run.metadata&.dig('by_dataset')&.keys&.join(', ') || '-'
        puts "| #{run.created_at.strftime('%Y-%m-%d %H:%M')} | #{run.total_tasks.to_s.rjust(9)} | #{run.accuracy_percentage.to_s.rjust(7)}% | #{datasets} |"
      end

      puts ""
      
      # Show trend if we have multiple runs
      if runs.size > 1
        first_accuracy = runs.last.accuracy_percentage
        latest_accuracy = runs.first.accuracy_percentage
        trend = latest_accuracy - first_accuracy

        puts "Trend: #{trend >= 0 ? '+' : ''}#{trend.round(1)}% since first run"
        
        if trend > 5
          puts "✅ System is IMPROVING over time"
        elsif trend > -5
          puts "⚠️ No significant change"
        else
          puts "❌ System is getting WORSE"
        end
      end

      puts "=" * 70
    end

    desc "Generate benchmark report (Markdown)"
    task report: :environment do
      entity = Entity.first

      unless entity
        puts "❌ No entity found"
        next
      end

      runs = BenchmarkRun.where(entity: entity, run_type: 'real_benchmark')
                        .order(created_at: :desc)
                        .limit(50)

      if runs.empty?
        puts "No benchmark runs found."
        next
      end

      # Generate markdown report
      report = <<~MD
        # AMOS Benchmark Report

        Generated: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}

        ## Summary

        - Total Runs: #{runs.size}
        - Latest Accuracy: #{runs.first.accuracy_percentage}%
        - Best Accuracy: #{runs.map(&:accuracy_percentage).max}%
        - Average Accuracy: #{(runs.map(&:accuracy_percentage).sum / runs.size).round(1)}%

        ## Historical Results

        | Date | Run ID | Questions | Correct | Accuracy |
        |------|--------|-----------|---------|----------|
        #{runs.map { |r| "| #{r.created_at.strftime('%Y-%m-%d')} | #{r.run_id[0..7]} | #{r.total_tasks} | #{r.correct_tasks} | #{r.accuracy_percentage}% |" }.join("\n")}

        ## Analysis

        #{analyze_trend(runs)}

        ## Recommendations

        #{generate_recommendations(runs)}
      MD

      filepath = Rails.root.join('docs', 'BENCHMARK_REPORT.md')
      File.write(filepath, report)
      
      puts "✅ Report saved to #{filepath}"
      puts ""
      puts report
    end

    def analyze_trend(runs)
      return "Not enough data for trend analysis." if runs.size < 3

      recent = runs.first(5).map(&:accuracy_percentage).sum / 5
      older = runs.last(5).map(&:accuracy_percentage).sum / 5
      trend = recent - older

      if trend > 5
        "**Positive Trend**: Accuracy has improved by #{trend.round(1)} percentage points. The system is learning and improving."
      elsif trend > -5
        "**Stable**: Accuracy has remained relatively stable (#{trend.round(1)} pp change). No significant improvement or degradation."
      else
        "**Negative Trend**: Accuracy has decreased by #{trend.abs.round(1)} percentage points. Investigation needed."
      end
    end

    def generate_recommendations(runs)
      latest = runs.first
      accuracy = latest&.accuracy_percentage || 0

      recommendations = []

      if accuracy < 50
        recommendations << "- **Critical**: Accuracy below 50%. Review agent prompts and tool configurations."
      elsif accuracy < 70
        recommendations << "- **Improvement needed**: Focus on failed question categories."
      elsif accuracy < 85
        recommendations << "- **Good progress**: Continue monitoring and fine-tuning."
      else
        recommendations << "- **Excellent**: Maintain current performance. Consider harder benchmarks."
      end

      if runs.size < 10
        recommendations << "- Run more benchmarks to establish reliable baseline."
      end

      recommendations.join("\n")
    end
  end
end

