# frozen_string_literal: true

class BenchmarkExecutionJob < ApplicationJob
  queue_as :benchmarks

  # Run a benchmark suite
  # @param category [String] 'all', 'quick', or a specific category name
  # @param run_type [String] 'quick' (5 tasks), 'standard' (25 tasks), 'full' (all tasks)
  # @param cleanup_before [Boolean] whether to clean up test data first
  # @param requested_by [Integer] user ID who requested the run
  def perform(category: 'all', run_type: 'quick', cleanup_before: true, requested_by: nil)
    Rails.logger.info "[Benchmark] Starting #{run_type} benchmark for category: #{category}"
    
    # Use isolated test environment
    runner = Benchmarks::BusinessBenchmarkRunner.new(
      use_test_env: true,
      cleanup_before: cleanup_before
    )

    # Create benchmark run record
    benchmark_run = BenchmarkRun.create!(
      run_id: runner.run_id,
      entity: runner.entity,
      user: runner.user,
      benchmark_category: category,
      run_type: run_type,
      metadata: {
        requested_by: requested_by,
        started_at: Time.current.iso8601,
        cleanup_before: cleanup_before
      }
    )

    # Select tasks based on run_type
    tasks = select_tasks(category, run_type)
    
    Rails.logger.info "[Benchmark] Running #{tasks.count} tasks..."

    # Run each task
    tasks.each_with_index do |task, idx|
      Rails.logger.info "[Benchmark] Task #{idx + 1}/#{tasks.count}: #{task[:id]} - #{task[:name]}"
      
      begin
        result = runner.run_task(task, use_scout: true, verify_assets: true)
        
        # Save task result
        BenchmarkTaskResult.create!(
          benchmark_run: benchmark_run,
          task_id: task[:id],
          agent_slug: 'scout',
          task_description: task[:request],
          expected_answer: task[:rubric].join("\n"),
          actual_answer: result[:response].to_s.truncate(10000),
          success: result[:success],
          correct: evaluate_correctness(result, task),
          asked_for_help: result[:agent_calls].to_i > 0,
          helper_used_slug: result[:agents_used]&.first,
          execution_time_ms: result[:elapsed_ms],
          raw_output: {
            tools_used: result[:tools_used],
            agents_used: result[:agents_used],
            tool_calls: result[:tool_calls],
            agent_calls: result[:agent_calls],
            grounded: result[:grounded],
            created_assets: result[:created_assets],
            agent_verifications: result[:agent_verifications],
            tool_verifications: result[:tool_verifications],
            integration_verifications: result[:integration_verifications],
            creation_summary: result[:creation_summary]
          }.compact
        )
        
        Rails.logger.info "[Benchmark]   ✓ #{result[:success] ? 'Success' : 'Failed'} (#{result[:elapsed_ms]}ms)"
        
      rescue => e
        Rails.logger.error "[Benchmark]   ✗ Error: #{e.message}"
        
        BenchmarkTaskResult.create!(
          benchmark_run: benchmark_run,
          task_id: task[:id],
          agent_slug: 'scout',
          task_description: task[:request],
          expected_answer: task[:rubric].join("\n"),
          actual_answer: "ERROR: #{e.message}",
          success: false,
          correct: false,
          execution_time_ms: 0,
          raw_output: { error: e.message, backtrace: e.backtrace.first(5) }
        )
      end
    end

    # Calculate summary stats
    benchmark_run.calculate_summary_stats!
    
    # Update metadata with completion info
    benchmark_run.update!(
      metadata: benchmark_run.metadata.merge(
        'completed_at' => Time.current.iso8601,
        'duration_seconds' => (Time.current - benchmark_run.created_at).round
      )
    )

    Rails.logger.info "[Benchmark] Complete! Accuracy: #{benchmark_run.overall_accuracy}%"
    
    # Notify if there are regressions compared to previous run
    check_for_regressions(benchmark_run)
    
  rescue => e
    Rails.logger.error "[Benchmark] Job failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  def select_tasks(category, run_type)
    all_tasks = if category == 'all'
      Benchmarks::BusinessBenchmark.all_tasks
    else
      Benchmarks::BusinessBenchmark.tasks_by_category(category.to_sym)
    end

    case run_type
    when 'quick'
      # 5 tasks - one from each major area
      sample_diverse(all_tasks, 5)
    when 'standard'
      # 25 tasks - good coverage
      sample_diverse(all_tasks, 25)
    when 'full'
      # All tasks
      all_tasks
    when 'creation_only'
      # Only tasks that create things
      all_tasks.select { |t| t[:creates_agent] || t[:creates_tool] || t[:creates_integration] || t[:creates_asset] }
    when 'grounded_only'
      # Only tasks requiring external data
      all_tasks.select { |t| t[:grounding_required] || t[:requires_tools] }
    else
      all_tasks.sample([run_type.to_i, 5].max)
    end
  end

  def sample_diverse(tasks, count)
    # Try to get tasks from different categories and difficulties
    by_category = tasks.group_by { |t| t[:category] }
    by_difficulty = tasks.group_by { |t| t[:difficulty] }
    
    selected = []
    
    # First, get one from each category
    by_category.each do |_cat, cat_tasks|
      selected << cat_tasks.sample if selected.size < count
    end
    
    # Fill remaining with diverse difficulties
    remaining = count - selected.size
    if remaining > 0
      available = tasks - selected
      [:easy, :medium, :hard].cycle.take(remaining).each do |diff|
        task = available.find { |t| t[:difficulty] == diff }
        task ||= available.sample
        if task
          selected << task
          available.delete(task)
        end
      end
    end
    
    selected.compact.uniq.take(count)
  end

  def evaluate_correctness(result, task)
    return false unless result[:success]
    
    # For creation tasks, check if assets were created and verified
    if task[:creates_agent] || task[:creates_tool] || task[:creates_integration] || task[:creates_asset]
      return result[:creation_success] == true || result[:verification_success] == true
    end
    
    # For grounded tasks, must have used tools/agents
    if task[:grounding_required] || task[:requires_tools]
      return false unless result[:grounded]
    end
    
    # For other tasks, check if response addresses rubric points
    # This is a simple heuristic - real scoring needs human review
    response = result[:response].to_s.downcase
    rubric_hits = task[:rubric].count do |point|
      keywords = point.downcase.split(/\s+/).select { |w| w.length > 3 }
      keywords.any? { |kw| response.include?(kw) }
    end
    
    # Consider correct if hits at least half the rubric points
    rubric_hits >= (task[:rubric].size / 2.0).ceil
  end

  def check_for_regressions(current_run)
    # Find previous run of same category
    previous_run = BenchmarkRun.where(benchmark_category: current_run.benchmark_category)
                               .where.not(id: current_run.id)
                               .order(created_at: :desc)
                               .first
    
    return unless previous_run

    # Compare accuracy
    accuracy_change = current_run.overall_accuracy.to_f - previous_run.overall_accuracy.to_f
    
    if accuracy_change < -5  # More than 5% regression
      Rails.logger.warn "[Benchmark] ⚠️ REGRESSION DETECTED: #{accuracy_change.round(1)}% drop from previous run"
      
      # Could send notification here
      # NotificationService.send_regression_alert(current_run, previous_run, accuracy_change)
    elsif accuracy_change > 5
      Rails.logger.info "[Benchmark] 🎉 IMPROVEMENT: +#{accuracy_change.round(1)}% from previous run"
    end
  end
end

