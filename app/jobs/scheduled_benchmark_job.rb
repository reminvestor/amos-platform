# frozen_string_literal: true

class ScheduledBenchmarkJob < ApplicationJob
  queue_as :default

  # Run a subset of benchmarks on a schedule to track performance over time
  def perform(entity_id = nil, options = {})
    entity = entity_id ? Entity.find(entity_id) : Entity.first
    return unless entity

    user = entity.users.first
    return unless user

    Rails.logger.info "[ScheduledBenchmark] Starting scheduled benchmark for entity #{entity.id}"

    # Run a quick benchmark suite
    run_quick_benchmark(entity, user, options)
  end

  private

  def run_quick_benchmark(entity, user, options)
    tracker = Collaboration::BenchmarkTracker.new(entity: entity)
    runner = Collaboration::BenchmarkRunner.new(entity: entity, user: user)

    # Start tracked run
    run = tracker.start_run(
      run_type: 'scheduled',
      category: 'mixed',
      collaboration_enabled: true,
      model: options[:model]
    )

    # Pick a sample of benchmarks from each category
    sample_size = options[:sample_size] || 2
    benchmarks = []

    Collaboration::PublicBenchmarks.all_benchmarks.each do |category, tasks|
      benchmarks.concat(tasks.sample(sample_size).map { |t| t.merge(category: category.to_s) })
    end

    # Pick an agent for each task
    results = []
    benchmarks.each do |benchmark|
      agent = pick_agent_for_benchmark(benchmark, entity)
      next unless agent

      result = runner.run_single_benchmark(
        agent_slug: agent.slug,
        task_id: benchmark[:id],
        allow_collaboration: true
      )

      tracker.record_task_result(
        task_id: benchmark[:id],
        category: benchmark[:category],
        difficulty: benchmark[:difficulty],
        answer: result[:answer],
        correct: result[:correct],
        execution_time_ms: result[:execution_time_ms],
        tokens_used: result[:tokens_used] || 0,
        asked_for_help: result[:asked_for_help],
        helper_used: result[:helper_used],
        collaboration_helped: result[:asked_for_help] && result[:correct],
        agent_plugin_id: agent.id
      )

      results << result
    end

    # Complete the run
    correct_count = results.count { |r| r[:correct] }
    tracker.complete_run(
      total_tasks: results.size,
      correct_count: correct_count,
      accuracy_percentage: results.size > 0 ? (correct_count.to_f / results.size * 100).round(1) : 0,
      avg_execution_time_ms: results.any? ? (results.sum { |r| r[:execution_time_ms] || 0 } / results.size).round : 0,
      total_tokens_used: results.sum { |r| r[:tokens_used] || 0 }
    )

    Rails.logger.info "[ScheduledBenchmark] Completed: #{correct_count}/#{results.size} correct (#{run.accuracy_percentage}%)"

    # Check for degradation and alert if needed
    check_for_degradation(entity, run)
  end

  def pick_agent_for_benchmark(benchmark, entity)
    case benchmark[:category]
    when 'gsm8k', 'math'
      AgentPlugin.find_by(slug: 'scout', entity: entity)
    when 'hotpot', 'knowledge'
      AgentPlugin.find_by(slug: 'web_research_specialist', entity: entity)
    when 'tool_use', 'weather'
      AgentPlugin.find_by(slug: 'weather_scout', entity: entity)
    when 'collaboration'
      AgentPlugin.find_by(slug: 'scout', entity: entity)
    else
      AgentPlugin.active.where(entity: entity).first
    end
  end

  def check_for_degradation(entity, current_run)
    # Get last 5 runs
    recent_runs = BenchmarkRun.where(entity: entity)
      .completed
      .where('created_at < ?', current_run.created_at)
      .order(created_at: :desc)
      .limit(5)

    return if recent_runs.empty?

    avg_accuracy = recent_runs.average(:accuracy_percentage)
    return unless avg_accuracy

    # Alert if current accuracy is significantly lower
    if current_run.accuracy_percentage < (avg_accuracy - 15)
      Rails.logger.warn "[ScheduledBenchmark] DEGRADATION DETECTED: Current accuracy #{current_run.accuracy_percentage}% vs average #{avg_accuracy.round(1)}%"
      
      # Could send notification here
      # NotificationService.alert_benchmark_degradation(entity, current_run, avg_accuracy)
    end
  end
end

