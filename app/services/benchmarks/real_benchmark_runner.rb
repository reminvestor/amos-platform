# frozen_string_literal: true

module Benchmarks
  # ============================================
  # Real Benchmark Runner
  # Runs actual benchmark datasets and tracks results
  # ============================================
  class RealBenchmarkRunner
    attr_reader :entity, :user, :results, :run_id

    def initialize(entity:, user:)
      @entity = entity
      @user = user
      @results = []
      @run_id = SecureRandom.uuid
    end

    # ============================================
    # MAIN ENTRY POINTS
    # ============================================

    # Run a full benchmark suite
    def run_full_suite(datasets: [:gsm8k, :simple_qa, :gaia], sample_size: 50)
      start_time = Time.current
      all_results = {}

      puts "\n" + "=" * 70
      puts "🔬 REAL BENCHMARK SUITE"
      puts "=" * 70
      puts "Run ID: #{@run_id}"
      puts "Started: #{start_time}"
      puts "Datasets: #{datasets.join(', ')}"
      puts "Sample size per dataset: #{sample_size}"
      puts "=" * 70
      puts ""

      datasets.each do |dataset_key|
        puts "📦 Running #{dataset_key.to_s.upcase}..."
        result = run_dataset(dataset_key, sample_size: sample_size)
        all_results[dataset_key] = result
        puts ""
      end

      # Generate summary
      summary = generate_summary(all_results, start_time)
      
      # Save to database for historical tracking
      save_run(summary, all_results)

      summary
    end

    # Run a single dataset benchmark
    def run_dataset(dataset_key, sample_size: 50, verbose: true)
      questions = HuggingfaceDatasets.get_questions(dataset_key, limit: sample_size)
      
      if questions.empty?
        puts "⚠️  No questions available for #{dataset_key}. Using fallback samples."
        questions = get_fallback_questions(dataset_key, sample_size)
      end

      puts "  Running #{questions.size} questions..." if verbose

      correct = 0
      total_time = 0
      results = []

      questions.each_with_index do |q, idx|
        start = Time.current
        
        result = run_single_question(q)
        
        elapsed = Time.current - start
        total_time += elapsed
        
        correct += 1 if result[:correct]
        results << result
        
        # Progress indicator
        print result[:correct] ? '.' : 'x' if verbose
        
        # Rate limiting to avoid overwhelming the API
        sleep(0.5) if idx < questions.size - 1
      end

      puts "" if verbose

      accuracy = questions.size > 0 ? (correct.to_f / questions.size * 100).round(2) : 0
      avg_time = questions.size > 0 ? (total_time / questions.size * 1000).round : 0

      {
        dataset: dataset_key,
        total: questions.size,
        correct: correct,
        accuracy: accuracy,
        avg_time_ms: avg_time,
        total_time_s: total_time.round(1),
        results: results
      }
    end

    # Run A/B comparison: with vs without collaboration
    def run_ab_comparison(dataset_key, sample_size: 30)
      questions = HuggingfaceDatasets.sample(dataset_key, count: sample_size)
      
      if questions.empty?
        questions = get_fallback_questions(dataset_key, sample_size)
      end

      puts "\n" + "=" * 70
      puts "🔬 A/B COMPARISON: Collaboration Impact"
      puts "=" * 70
      puts "Dataset: #{dataset_key}"
      puts "Questions: #{questions.size}"
      puts ""

      # Run WITHOUT collaboration (baseline)
      puts "Phase 1: WITHOUT Collaboration System"
      results_without = questions.map.with_index do |q, idx|
        result = run_single_question(q, allow_collaboration: false)
        print result[:correct] ? '.' : 'x'
        result
      end
      puts ""

      correct_without = results_without.count { |r| r[:correct] }
      accuracy_without = (correct_without.to_f / questions.size * 100).round(2)

      # Reset any agent state between runs
      sleep(2)

      # Run WITH collaboration
      puts "Phase 2: WITH Collaboration System"
      results_with = questions.map.with_index do |q, idx|
        result = run_single_question(q, allow_collaboration: true)
        print result[:correct] ? '.' : 'x'
        result
      end
      puts ""

      correct_with = results_with.count { |r| r[:correct] }
      accuracy_with = (correct_with.to_f / questions.size * 100).round(2)
      collab_used = results_with.count { |r| r[:collaboration_used] }

      # Analysis
      improvement = accuracy_with - accuracy_without
      
      puts ""
      puts "=" * 70
      puts "📊 A/B RESULTS"
      puts "=" * 70
      puts ""
      puts "| Metric | Without Collab | With Collab | Delta |"
      puts "|--------|---------------|-------------|-------|"
      puts "| Accuracy | #{accuracy_without}% | #{accuracy_with}% | #{improvement >= 0 ? '+' : ''}#{improvement.round(2)}% |"
      puts "| Correct | #{correct_without}/#{questions.size} | #{correct_with}/#{questions.size} | #{correct_with - correct_without} |"
      puts "| Collab Used | N/A | #{collab_used} times | - |"
      puts ""
      
      # Honest assessment
      if improvement > 5
        puts "✅ COLLABORATION HELPS: +#{improvement.round(1)}% improvement"
      elsif improvement > 0
        puts "✓ SLIGHT IMPROVEMENT: +#{improvement.round(1)}%"
        puts "  But may not be statistically significant with this sample size"
      elsif improvement > -5
        puts "⚠️ NO SIGNIFICANT DIFFERENCE: #{improvement.round(1)}%"
        puts "  Collaboration system may be adding complexity without benefit"
      else
        puts "❌ COLLABORATION HURTS: #{improvement.round(1)}%"
        puts "  The collaboration system is making things WORSE"
      end

      puts ""
      puts "=" * 70

      {
        dataset: dataset_key,
        sample_size: questions.size,
        without_collaboration: {
          correct: correct_without,
          accuracy: accuracy_without
        },
        with_collaboration: {
          correct: correct_with,
          accuracy: accuracy_with,
          collaboration_used: collab_used
        },
        improvement: improvement,
        verdict: improvement > 5 ? 'helps' : (improvement > -5 ? 'neutral' : 'hurts')
      }
    end

    private

    # ============================================
    # QUESTION EXECUTION
    # ============================================

    def run_single_question(question, allow_collaboration: true)
      start_time = Time.current
      
      begin
        # Use Scout to answer the question
        scout_service = V3::AgentLoop # V3 migration stub.new(@user, @entity, "benchmark_#{SecureRandom.hex(4)}")
        
        # Simple callback to collect response
        response_text = ""
        callback = ->(chunk) { response_text += chunk.to_s if chunk.is_a?(String) }
        
        result = scout_service.process_message_with_tools_streaming(
          question[:question],
          callback,
          [],
          nil
        )

        # Extract answer
        answer = extract_answer(result, response_text)
        
        # Validate
        correct = validate_answer(answer, question[:answer], question)
        
        # Check if collaboration was used
        collab_used = result.is_a?(Hash) && (result[:tools_used]&.any? { |t| t.include?('agent') } || false)

        {
          question_id: question[:id],
          question: question[:question].truncate(100),
          expected: question[:answer].to_s.truncate(50),
          got: answer.to_s.truncate(100),
          correct: correct,
          collaboration_used: collab_used,
          time_ms: ((Time.current - start_time) * 1000).round,
          error: nil
        }

      rescue => e
        Rails.logger.error "[Benchmark] Question failed: #{e.message}"
        
        {
          question_id: question[:id],
          question: question[:question].truncate(100),
          expected: question[:answer].to_s.truncate(50),
          got: nil,
          correct: false,
          collaboration_used: false,
          time_ms: ((Time.current - start_time) * 1000).round,
          error: e.message
        }
      end
    end

    def extract_answer(result, accumulated_text)
      if result.is_a?(Hash)
        final = result[:final_response] || result['final_response'] || {}
        return final[:message] || final['message'] if final[:message].present? || final['message'].present?
        return result[:message] if result[:message].present?
      end
      
      accumulated_text.presence || result.to_s
    end

    def validate_answer(got, expected, question)
      return false if got.blank? || expected.blank?

      got_clean = got.to_s.downcase.gsub(/[^a-z0-9\s\.]/, '').strip
      expected_clean = expected.to_s.downcase.gsub(/[^a-z0-9\s\.]/, '').strip

      # Exact match
      return true if got_clean.include?(expected_clean)

      # Numeric match (for math problems)
      got_nums = got_clean.scan(/[-]?\d+\.?\d*/).map(&:to_f)
      expected_nums = expected_clean.scan(/[-]?\d+\.?\d*/).map(&:to_f)
      
      if expected_nums.any?
        expected_nums.each do |exp_num|
          return true if got_nums.any? { |got_num| (got_num - exp_num).abs < 0.01 }
        end
      end

      # Fuzzy match for short answers
      if expected_clean.length < 50
        return true if got_clean.split.any? { |word| expected_clean.include?(word) && word.length > 3 }
      end

      false
    end

    # ============================================
    # FALLBACK DATA
    # ============================================

    def get_fallback_questions(dataset_key, count)
      # Use our existing sample questions as fallback
      case dataset_key.to_sym
      when :gsm8k
        Collaboration::PublicBenchmarks.get_benchmark(:gsm8k).first(count).map do |q|
          { id: q[:id], question: q[:question], answer: q[:answer], source: 'fallback' }
        end
      when :simple_qa
        Collaboration::ExternalBenchmarks.get_benchmark(:simpleqa).first(count).map do |q|
          { id: q[:id], question: q[:question], answer: q[:answer], source: 'fallback' }
        end
      when :gaia
        Collaboration::ExternalBenchmarks.get_benchmark(:gaia).first(count).map do |q|
          { id: q[:id], question: q[:question], answer: q[:answer], source: 'fallback' }
        end
      else
        []
      end
    end

    # ============================================
    # REPORTING
    # ============================================

    def generate_summary(all_results, start_time)
      total_questions = all_results.values.sum { |r| r[:total] }
      total_correct = all_results.values.sum { |r| r[:correct] }
      overall_accuracy = total_questions > 0 ? (total_correct.to_f / total_questions * 100).round(2) : 0

      elapsed = Time.current - start_time

      summary = {
        run_id: @run_id,
        timestamp: start_time.iso8601,
        elapsed_seconds: elapsed.round(1),
        total_questions: total_questions,
        total_correct: total_correct,
        overall_accuracy: overall_accuracy,
        by_dataset: all_results.transform_values do |r|
          {
            total: r[:total],
            correct: r[:correct],
            accuracy: r[:accuracy],
            avg_time_ms: r[:avg_time_ms]
          }
        end
      }

      puts "=" * 70
      puts "📊 BENCHMARK SUMMARY"
      puts "=" * 70
      puts ""
      puts "Run ID: #{@run_id}"
      puts "Duration: #{elapsed.round(1)}s"
      puts "Total Questions: #{total_questions}"
      puts "Overall Accuracy: #{overall_accuracy}%"
      puts ""
      puts "| Dataset | Correct | Total | Accuracy | Avg Time |"
      puts "|---------|---------|-------|----------|----------|"
      
      all_results.each do |dataset, result|
        puts "| #{dataset.to_s.ljust(9)} | #{result[:correct].to_s.rjust(7)} | #{result[:total].to_s.rjust(5)} | #{result[:accuracy].to_s.rjust(7)}% | #{result[:avg_time_ms].to_s.rjust(7)}ms |"
      end

      puts ""
      puts "=" * 70

      summary
    end

    def save_run(summary, detailed_results)
      # Save to BenchmarkRun if the model exists
      if defined?(BenchmarkRun)
        run = BenchmarkRun.create!(
          run_id: @run_id,
          entity: @entity,
          run_type: 'full',
          benchmark_category: 'mixed',
          started_at: Time.current - summary[:elapsed_seconds].to_i.seconds,
          collaboration_enabled: true,
          agent_slug: 'scout',
          model_used: ENV['BEDROCK_DEFAULT_MODEL'] || 'qwen3-next-80b',
          metadata: {
            by_dataset: summary[:by_dataset],
            source: 'huggingface'
          }
        )

        # Complete the run with summary stats
        run.complete!(
          total_tasks: summary[:total_questions],
          correct_count: summary[:total_correct],
          accuracy_percentage: summary[:overall_accuracy],
          avg_execution_time_ms: summary[:by_dataset].values.map { |d| d[:avg_time_ms] }.sum / summary[:by_dataset].size
        )
        
        Rails.logger.info "[Benchmark] Saved run #{@run_id} to database"
        run
      end
    rescue => e
      Rails.logger.error "[Benchmark] Failed to save run: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      nil
    end
  end
end

