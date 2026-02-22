# frozen_string_literal: true

module Benchmarks
  module V2
    # Comparator - Git-aware benchmark comparison and regression detection
    #
    # After each benchmark run, compares scores to the baseline (last known good).
    # Detects regressions (score drops > 10%) and improvements (score gains > 5%).
    # Generates commit-level scorecards for tracking platform quality over time.
    #
    # Baselines are stored as metadata on BenchmarkRun records.
    #
    # Usage:
    #   comparator = Benchmarks::V2::Comparator.new
    #   report = comparator.compare(benchmark_run)
    #   comparator.update_baselines!(benchmark_run)
    #
    class Comparator
      REGRESSION_THRESHOLD = -10  # Score drop > 10% = regression
      IMPROVEMENT_THRESHOLD = 5   # Score gain > 5% = improvement
      BASELINE_KEY = "benchmark_v2_baselines"

      # Compare a benchmark run against the baseline
      # Returns a structured comparison report
      def compare(benchmark_run)
        baseline = load_baselines
        current_scores = extract_scores(benchmark_run)

        comparison = {}
        regressions = []
        improvements = []

        current_scores.each do |scenario_id, current_score|
          baseline_score = baseline[scenario_id]

          if baseline_score.nil?
            comparison[scenario_id] = {
              current: current_score,
              baseline: nil,
              delta: nil,
              status: :new
            }
            next
          end

          delta = current_score - baseline_score
          delta_pct = baseline_score > 0 ? ((delta.to_f / baseline_score) * 100).round(1) : 0

          status = if delta_pct <= REGRESSION_THRESHOLD
                     regressions << scenario_id
                     :regression
                   elsif delta_pct >= IMPROVEMENT_THRESHOLD
                     improvements << scenario_id
                     :improvement
                   else
                     :stable
                   end

          comparison[scenario_id] = {
            current: current_score,
            baseline: baseline_score,
            delta: delta,
            delta_pct: delta_pct,
            status: status
          }
        end

        overall_current = current_scores.values.sum.to_f / [current_scores.size, 1].max
        baseline_scores = baseline.slice(*current_scores.keys)
        overall_baseline = baseline_scores.any? ? baseline_scores.values.sum.to_f / baseline_scores.size : nil
        overall_delta = overall_baseline ? (overall_current - overall_baseline).round(1) : nil

        {
          git_commit: benchmark_run.git_commit,
          run_id: benchmark_run.run_id,
          compared_at: Time.current.iso8601,
          overall: {
            current_avg: overall_current.round(1),
            baseline_avg: overall_baseline&.round(1),
            delta: overall_delta,
            delta_pct: overall_baseline && overall_baseline > 0 ? ((overall_delta / overall_baseline) * 100).round(1) : nil
          },
          regressions: regressions,
          improvements: improvements,
          scenario_comparisons: comparison,
          scorecard: generate_scorecard(benchmark_run, comparison, regressions, improvements)
        }
      end

      # Update baselines when scores improve
      def update_baselines!(benchmark_run)
        baseline = load_baselines
        current_scores = extract_scores(benchmark_run)

        updated = false
        current_scores.each do |scenario_id, score|
          old = baseline[scenario_id]
          if old.nil? || score > old
            baseline[scenario_id] = score
            updated = true
          end
        end

        save_baselines!(baseline, benchmark_run.git_commit) if updated
        updated
      end

      # Get the current baselines
      def baselines
        load_baselines
      end

      # Get historical trend for a scenario
      def trend(scenario_id, limit: 20)
        BenchmarkTaskResult
          .where(task_id: scenario_id.to_s)
          .joins(:benchmark_run)
          .where(benchmark_runs: { run_type: "v2_benchmark" })
          .order(created_at: :desc)
          .limit(limit)
          .pluck(:created_at, Arel.sql("benchmark_runs.git_commit"), Arel.sql("benchmark_task_results.metadata->>'total_score'"))
          .map { |ts, commit, score| { at: ts, commit: commit, score: score.to_i } }
          .reverse
      end

      private

      def extract_scores(benchmark_run)
        scores = {}
        benchmark_run.task_results.each do |result|
          scores[result.task_id] = result.metadata&.dig("total_score").to_i
        end
        scores
      end

      def load_baselines
        record = BenchmarkRun
                   .where(run_type: "v2_benchmark")
                   .where("metadata->>'is_baseline' = 'true'")
                   .order(created_at: :desc)
                   .first

        return {} unless record
        record.metadata&.dig("baselines") || {}
      end

      def save_baselines!(baselines, commit)
        BenchmarkRun
          .where(run_type: "v2_benchmark")
          .where("metadata->>'is_baseline' = 'true'")
          .update_all("metadata = metadata || '{\"is_baseline\": false}'::jsonb")

        BenchmarkRun.create!(
          entity: Entity.find_by(slug: "amos-labs") || Entity.first,
          run_type: "v2_benchmark",
          benchmark_category: "baseline_update",
          agent_slug: "v3_agent_loop",
          git_commit: commit,
          started_at: Time.current,
          completed_at: Time.current,
          total_tasks: baselines.size,
          metadata: {
            is_baseline: true,
            baselines: baselines,
            updated_at: Time.current.iso8601
          }
        )
      end

      def generate_scorecard(benchmark_run, comparison, regressions, improvements)
        lines = []
        lines << "# Benchmark Scorecard"
        lines << "Commit: #{benchmark_run.git_commit || 'unknown'}"
        lines << "Run: #{benchmark_run.run_id}"
        lines << ""

        if regressions.any?
          lines << "## REGRESSIONS (#{regressions.size})"
          regressions.each do |sid|
            c = comparison[sid]
            lines << "  - #{sid}: #{c[:baseline]} -> #{c[:current]} (#{c[:delta_pct]}%)"
          end
          lines << ""
        end

        if improvements.any?
          lines << "## IMPROVEMENTS (#{improvements.size})"
          improvements.each do |sid|
            c = comparison[sid]
            lines << "  + #{sid}: #{c[:baseline]} -> #{c[:current]} (+#{c[:delta_pct]}%)"
          end
          lines << ""
        end

        stable = comparison.select { |_, c| c[:status] == :stable }
        if stable.any?
          lines << "## STABLE (#{stable.size})"
          stable.each do |sid, c|
            lines << "  = #{sid}: #{c[:current]} (baseline: #{c[:baseline]})"
          end
        end

        lines.join("\n")
      end
    end
  end
end
