# frozen_string_literal: true

module Collaboration
  class BenchmarkTracker
    attr_reader :entity, :current_run

    def initialize(entity:)
      @entity = entity
      @current_run = nil
    end

    # ============================================
    # RUN MANAGEMENT
    # ============================================

    def start_run(run_type:, category: nil, agent_slug: nil, collaboration_enabled: true, model: nil)
      @current_run = BenchmarkRun.create!(
        entity: @entity,
        run_type: run_type,
        benchmark_category: category,
        agent_slug: agent_slug,
        collaboration_enabled: collaboration_enabled,
        model_used: model || default_model,
        git_commit: current_git_commit,
        started_at: Time.current,
        metadata: {
          ruby_version: RUBY_VERSION,
          rails_version: Rails.version,
          hostname: Socket.gethostname
        }
      )

      Rails.logger.info "[BenchmarkTracker] Started run #{@current_run.run_id} (#{run_type})"
      @current_run
    end

    def record_task_result(result)
      return unless @current_run

      benchmark = find_benchmark(result[:task_id])

      BenchmarkTaskResult.create!(
        benchmark_run: @current_run,
        agent_plugin_id: result[:agent_plugin_id],
        agent_plugin_execution_id: result[:execution_id],
        task_id: result[:task_id],
        category: benchmark&.dig(:category) || result[:category],
        difficulty: benchmark&.dig(:difficulty) || result[:difficulty],
        question: benchmark&.dig(:question) || result[:question],
        expected_answer: benchmark&.dig(:answer)&.to_s,
        actual_answer: result[:answer],
        correct: result[:correct],
        execution_time_ms: result[:execution_time_ms],
        tokens_used: result[:tokens_used],
        cost_cents: result[:cost_cents],
        asked_for_help: result[:asked_for_help] || false,
        helper_agent_slug: result[:helper_used],
        collaboration_helped: result[:collaboration_helped] || false,
        metadata: result[:metadata] || {}
      )
    end

    def complete_run(summary = {})
      return unless @current_run

      @current_run.complete!(summary)
      Rails.logger.info "[BenchmarkTracker] Completed run #{@current_run.run_id} - Accuracy: #{@current_run.accuracy_percentage}%"
      @current_run
    end

    # ============================================
    # REPORTING
    # ============================================

    def self.generate_report(entity:, days: 30)
      runs = BenchmarkRun.where(entity: entity)
        .where('created_at > ?', days.days.ago)
        .completed
        .order(created_at: :desc)

      {
        generated_at: Time.current.iso8601,
        period_days: days,
        entity_id: entity.id,
        summary: generate_summary(runs),
        trends: generate_trends(runs),
        by_category: generate_category_breakdown(runs),
        collaboration_analysis: generate_collaboration_analysis(runs),
        recent_runs: runs.limit(10).map(&:to_report)
      }
    end

    def self.generate_summary(runs)
      return {} if runs.empty?

      {
        total_runs: runs.count,
        total_tasks: runs.sum(:total_tasks),
        overall_accuracy: weighted_accuracy(runs),
        avg_execution_time_ms: runs.average(:avg_execution_time_ms)&.round,
        total_tokens: runs.sum(:total_tokens_used),
        total_cost_cents: runs.sum(:total_cost_cents).round(2),
        collaboration_rate: (runs.sum(:collaboration_requests).to_f / runs.sum(:total_tasks) * 100).round(1),
        collaboration_effectiveness: collaboration_effectiveness(runs)
      }
    end

    def self.generate_trends(runs)
      # Group by week
      weekly = runs.group_by { |r| r.created_at.beginning_of_week }
        .transform_values do |week_runs|
          {
            runs: week_runs.count,
            accuracy: weighted_accuracy(week_runs),
            collab_rate: (week_runs.sum(&:collaboration_requests).to_f / week_runs.sum(&:total_tasks) * 100).round(1)
          }
        end

      {
        weekly: weekly.sort.last(8).to_h,
        accuracy_trend: calculate_trend(runs.map(&:accuracy_percentage)),
        collaboration_trend: calculate_trend(runs.map(&:collaboration_rate))
      }
    end

    def self.generate_category_breakdown(runs)
      BenchmarkRun::CATEGORIES.map do |category|
        cat_runs = runs.for_category(category)
        next if cat_runs.empty?

        {
          category: category,
          runs: cat_runs.count,
          accuracy: weighted_accuracy(cat_runs),
          best_agent: best_performing_agent(cat_runs),
          avg_time_ms: cat_runs.average(:avg_execution_time_ms)&.round
        }
      end.compact
    end

    def self.generate_collaboration_analysis(runs)
      with_collab = runs.with_collaboration
      without_collab = runs.without_collaboration

      {
        with_collaboration: {
          runs: with_collab.count,
          accuracy: weighted_accuracy(with_collab),
          avg_requests_per_run: with_collab.average(:collaboration_requests)&.round(1)
        },
        without_collaboration: {
          runs: without_collab.count,
          accuracy: weighted_accuracy(without_collab)
        },
        improvement: improvement_from_collaboration(with_collab, without_collab),
        most_helpful_agents: most_helpful_agents(runs),
        tasks_where_collab_helped: BenchmarkTaskResult
          .joins(:benchmark_run)
          .where(benchmark_runs: { entity_id: runs.first&.entity_id })
          .collaboration_helped
          .count
      }
    end

    def self.export_to_json(entity:, days: 30)
      report = generate_report(entity: entity, days: days)
      JSON.pretty_generate(report)
    end

    def self.export_to_markdown(entity:, days: 30)
      report = generate_report(entity: entity, days: days)
      generate_markdown(report)
    end

    private

    def find_benchmark(task_id)
      PublicBenchmarks.all_benchmarks.values.flatten.find { |b| b[:id] == task_id }
    end

    def default_model
      ENV.fetch('DEFAULT_AI_MODEL', 'claude-sonnet-4-5-20250929')
    end

    def current_git_commit
      `git rev-parse --short HEAD 2>/dev/null`.strip.presence
    end

    def self.weighted_accuracy(runs)
      return 0 if runs.empty?
      total_tasks = runs.sum(&:total_tasks)
      return 0 if total_tasks.zero?
      
      weighted_sum = runs.sum { |r| (r.accuracy_percentage || 0) * r.total_tasks }
      (weighted_sum / total_tasks).round(1)
    end

    def self.collaboration_effectiveness(runs)
      total_requests = runs.sum(&:collaboration_requests)
      return 0 if total_requests.zero?
      
      helped = runs.sum(&:collaboration_helped_count)
      (helped.to_f / total_requests * 100).round(1)
    end

    def self.calculate_trend(values)
      return 'stable' if values.size < 2
      
      recent = values.last(3).sum / [values.last(3).size, 1].max
      older = values.first(3).sum / [values.first(3).size, 1].max
      
      diff = recent - older
      
      if diff > 5
        'improving'
      elsif diff < -5
        'declining'
      else
        'stable'
      end
    end

    def self.best_performing_agent(runs)
      runs.group_by(&:agent_slug)
        .transform_values { |agent_runs| weighted_accuracy(agent_runs) }
        .max_by { |_, acc| acc }
        &.first
    end

    def self.improvement_from_collaboration(with_collab, without_collab)
      with_acc = weighted_accuracy(with_collab)
      without_acc = weighted_accuracy(without_collab)
      
      {
        percentage_points: (with_acc - without_acc).round(1),
        relative_improvement: without_acc > 0 ? ((with_acc - without_acc) / without_acc * 100).round(1) : 0
      }
    end

    def self.most_helpful_agents(runs)
      BenchmarkTaskResult
        .joins(:benchmark_run)
        .where(benchmark_runs: { id: runs.pluck(:id) })
        .where.not(helper_agent_slug: nil)
        .where(collaboration_helped: true)
        .group(:helper_agent_slug)
        .count
        .sort_by { |_, count| -count }
        .first(5)
        .to_h
    end

    def self.generate_markdown(report)
      md = []
      md << "# Agent Collaboration Benchmark Report"
      md << ""
      md << "Generated: #{report[:generated_at]}"
      md << "Period: Last #{report[:period_days]} days"
      md << ""
      
      md << "## Summary"
      md << ""
      s = report[:summary]
      md << "| Metric | Value |"
      md << "|--------|-------|"
      md << "| Total Runs | #{s[:total_runs]} |"
      md << "| Total Tasks | #{s[:total_tasks]} |"
      md << "| Overall Accuracy | #{s[:overall_accuracy]}% |"
      md << "| Avg Execution Time | #{s[:avg_execution_time_ms]}ms |"
      md << "| Collaboration Rate | #{s[:collaboration_rate]}% |"
      md << "| Collaboration Effectiveness | #{s[:collaboration_effectiveness]}% |"
      md << ""
      
      md << "## Collaboration Impact"
      md << ""
      ca = report[:collaboration_analysis]
      md << "| Mode | Runs | Accuracy |"
      md << "|------|------|----------|"
      md << "| With Collaboration | #{ca[:with_collaboration][:runs]} | #{ca[:with_collaboration][:accuracy]}% |"
      md << "| Without Collaboration | #{ca[:without_collaboration][:runs]} | #{ca[:without_collaboration][:accuracy]}% |"
      md << ""
      md << "**Improvement from Collaboration:** #{ca[:improvement][:percentage_points]} percentage points (#{ca[:improvement][:relative_improvement]}% relative)"
      md << ""
      
      md << "## Performance by Category"
      md << ""
      md << "| Category | Runs | Accuracy | Best Agent |"
      md << "|----------|------|----------|------------|"
      report[:by_category].each do |cat|
        md << "| #{cat[:category]} | #{cat[:runs]} | #{cat[:accuracy]}% | #{cat[:best_agent]} |"
      end
      md << ""
      
      md << "## Trends"
      md << ""
      md << "- Accuracy Trend: **#{report[:trends][:accuracy_trend]}**"
      md << "- Collaboration Trend: **#{report[:trends][:collaboration_trend]}**"
      md << ""
      
      if ca[:most_helpful_agents].any?
        md << "## Most Helpful Agents"
        md << ""
        ca[:most_helpful_agents].each do |agent, count|
          md << "- #{agent}: #{count} times"
        end
      end
      
      md.join("\n")
    end
  end
end

