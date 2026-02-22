# frozen_string_literal: true

module AmosChecks
  module Improvement
    # BenchmarkRegressionCheck - Detects benchmark score regressions
    #
    # Compares the most recent v2 benchmark run to the stored baseline.
    # Creates findings for any scenario that regressed by > 10%.
    # This is the critical link in the RSI loop: regression -> signal -> bounty -> fix -> deploy.
    #
    class BenchmarkRegressionCheck < AmosChecks::BaseCheck
      def self.check_name  = :benchmark_regression
      def self.category    = :platform_improvement
      def self.description = "Detects benchmark score regressions after code changes"

      def run(entity: nil)
        latest_run = BenchmarkRun
                       .where(run_type: "v2_benchmark")
                       .where.not(benchmark_category: "baseline_update")
                       .where.not(completed_at: nil)
                       .order(created_at: :desc)
                       .first

        return [] unless latest_run

        comparator = Benchmarks::V2::Comparator.new
        report = comparator.compare(latest_run)

        findings = []

        if report[:regressions].any?
          regressed_scenarios = report[:regressions].map do |sid|
            c = report[:scenario_comparisons][sid]
            "#{sid}: #{c[:baseline]} -> #{c[:current]} (#{c[:delta_pct]}%)"
          end

          overall_delta = report.dig(:overall, :delta_pct)
          severity = if overall_delta && overall_delta <= -20
                       :critical
                     elsif report[:regressions].size >= 3
                       :critical
                     else
                       :high
                     end

          findings << build_finding(
            severity: severity,
            summary: "Benchmark regression: #{report[:regressions].size} scenario(s) dropped after commit #{latest_run.git_commit}",
            details: {
              git_commit: latest_run.git_commit,
              run_id: latest_run.run_id,
              overall_delta_pct: overall_delta,
              regressed_scenarios: regressed_scenarios,
              regression_count: report[:regressions].size,
              scorecard: report[:scorecard]
            },
            suggested_action: :create_bounty,
            bounty_params: {
              title: "Benchmark Regression: #{report[:regressions].size} scenario(s) degraded (commit #{latest_run.git_commit})",
              description: "The following benchmark scenarios regressed after commit #{latest_run.git_commit}:\n\n" \
                           "#{regressed_scenarios.map { |s| "- #{s}" }.join("\n")}\n\n" \
                           "Overall change: #{overall_delta}%\n\n" \
                           "Investigate the changes in this commit and fix the regressions.",
              bounty_type: "bug",
              points: severity == :critical ? 200 : 100
            }
          )
        end

        findings
      end
    end
  end
end
