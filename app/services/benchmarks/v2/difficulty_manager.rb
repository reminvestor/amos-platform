# frozen_string_literal: true

module Benchmarks
  module V2
    # DifficultyManager - Progressive difficulty and mastery tracking
    #
    # The benchmark system should always be uncomfortable:
    #   - Mastered scenarios (score > 95 for 5+ consecutive runs) still run but
    #     don't count toward the "improvement needed" metric
    #   - As lower levels are mastered, higher levels get more weight
    #   - If overall score > 90%, the system flags that benchmarks need to be harder
    #
    # This is the policy layer that drives RSI: the system can never rest.
    #
    # Usage:
    #   dm = Benchmarks::V2::DifficultyManager.new
    #   dm.mastered_scenarios                 # => [:landing_page_multi_section, ...]
    #   dm.weighted_suite                     # => scenarios with difficulty weights
    #   dm.comfort_alert?                     # => true if overall score too high
    #
    class DifficultyManager
      MASTERY_THRESHOLD = 95        # Score to consider a scenario "mastered"
      MASTERY_STREAK = 5            # Consecutive runs needed for mastery
      COMFORT_ZONE_THRESHOLD = 90   # Overall score above this = too easy
      DISCOMFORT_TARGET = 70        # Where the overall score SHOULD be

      LEVEL_WEIGHTS = {
        L1: 0.5,   # Easy -- kept for regression only, low weight
        L2: 1.0,   # Baseline difficulty
        L3: 1.5,   # Real-world complexity -- weighted higher
        L4: 2.0,   # Adversarial -- hardest synthetic
        L5: 2.5    # Mined from failures -- hardest overall
      }.freeze

      # Get all mastered scenario IDs
      def mastered_scenarios
        @mastered_scenarios ||= compute_mastered
      end

      # Get scenarios that still need improvement
      def unmastered_scenarios
        ScenarioLibrary.ids - mastered_scenarios
      end

      # Generate a weighted score for a benchmark run
      # Mastered scenarios contribute less to the "improvement needed" metric
      def weighted_score(results)
        return 0 if results.empty?

        total_weighted_score = 0
        total_weight = 0

        results.each do |result|
          scenario = ScenarioLibrary.get(result[:scenario_id]&.to_sym)
          next unless scenario

          level_weight = LEVEL_WEIGHTS[scenario.level] || 1.0
          mastery_factor = mastered_scenarios.include?(scenario.id) ? 0.3 : 1.0
          weight = level_weight * mastery_factor

          total_weighted_score += (result.dig(:score, :total_score) || 0) * weight
          total_weight += weight
        end

        total_weight > 0 ? (total_weighted_score / total_weight).round(1) : 0
      end

      # Check if the system is in the "comfort zone" (too easy)
      def comfort_alert?
        recent_averages = recent_average_scores(5)
        return false if recent_averages.size < 3

        recent_averages.all? { |avg| avg >= COMFORT_ZONE_THRESHOLD }
      end

      # Get a comfort report
      def comfort_report
        recent_avgs = recent_average_scores(10)
        mastered = mastered_scenarios
        total = ScenarioLibrary.count

        {
          mastered_count: mastered.size,
          total_scenarios: total,
          mastery_rate: total > 0 ? (mastered.size.to_f / total * 100).round(1) : 0,
          recent_averages: recent_avgs,
          in_comfort_zone: comfort_alert?,
          weighted_unmastered_avg: unmastered_average,
          recommendation: build_recommendation(mastered.size, total, recent_avgs)
        }
      end

      # Get difficulty distribution for the current suite
      def level_distribution
        distribution = {}
        Scenario::LEVELS.each do |level|
          scenarios = ScenarioLibrary.by_level(level)
          mastered_count = scenarios.count { |s| mastered_scenarios.include?(s.id) }
          distribution[level] = {
            total: scenarios.size,
            mastered: mastered_count,
            unmastered: scenarios.size - mastered_count,
            weight: LEVEL_WEIGHTS[level]
          }
        end
        distribution
      end

      private

      def compute_mastered
        mastered = []

        ScenarioLibrary.ids.each do |scenario_id|
          recent_scores = BenchmarkTaskResult
                            .where(task_id: scenario_id.to_s)
                            .joins(:benchmark_run)
                            .where(benchmark_runs: { run_type: "v2_benchmark" })
                            .order(created_at: :desc)
                            .limit(MASTERY_STREAK)
                            .pluck(Arel.sql("benchmark_task_results.metadata->>'total_score'"))
                            .map(&:to_i)

          next if recent_scores.size < MASTERY_STREAK
          mastered << scenario_id if recent_scores.all? { |s| s >= MASTERY_THRESHOLD }
        end

        mastered
      end

      def recent_average_scores(count)
        BenchmarkRun
          .where(run_type: "v2_benchmark")
          .where.not(benchmark_category: "baseline_update")
          .where.not(completed_at: nil)
          .order(created_at: :desc)
          .limit(count)
          .pluck(:accuracy_percentage)
          .compact
          .map(&:to_f)
      end

      def unmastered_average
        unmastered = unmastered_scenarios
        return 0 if unmastered.empty?

        scores = unmastered.filter_map do |sid|
          BenchmarkTaskResult
            .where(task_id: sid.to_s)
            .joins(:benchmark_run)
            .where(benchmark_runs: { run_type: "v2_benchmark" })
            .order(created_at: :desc)
            .limit(1)
            .pick(Arel.sql("benchmark_task_results.metadata->>'total_score'"))
            &.to_i
        end

        scores.any? ? (scores.sum.to_f / scores.size).round(1) : 0
      end

      def build_recommendation(mastered_count, total, recent_avgs)
        if comfort_alert?
          "BENCHMARKS TOO EASY: Overall scores consistently above #{COMFORT_ZONE_THRESHOLD}%. " \
          "Mine new scenarios from recent user failures or add harder L4/L5 scenarios. " \
          "Target overall score should be around #{DISCOMFORT_TARGET}%."
        elsif mastered_count > total * 0.7
          "Most scenarios mastered (#{mastered_count}/#{total}). " \
          "Consider adding new L3-L5 scenarios to maintain improvement pressure."
        elsif recent_avgs.any? && recent_avgs.first < 50
          "Scores are low (#{recent_avgs.first}%). Focus on fixing core capabilities before adding harder scenarios."
        else
          "Benchmark difficulty is well-calibrated. Keep pushing on unmastered scenarios."
        end
      end
    end
  end
end
