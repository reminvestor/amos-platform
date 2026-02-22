# frozen_string_literal: true

# ContinuousBenchmarkJob - Runs benchmark suite on a schedule
#
# Runs every 6 hours via recurring.yml. Uses the full scenario suite
# and compares to baselines. Unlike PostDeployBenchmarkJob which only
# runs on deploy, this catches regressions from config changes,
# data drift, or external service changes.
#
class ContinuousBenchmarkJob < ApplicationJob
  queue_as :living_platform

  def perform
    Rails.logger.info "[ContinuousBenchmark] Starting scheduled benchmark run"

    entity = Entity.find_by(slug: "amos-labs") || Entity.first
    user = entity&.users&.first
    return unless entity && user

    runner = Benchmarks::V2::Runner.new(
      entity: entity,
      user: user,
      run_type: "v2_benchmark"
    )

    results = runner.run_suite(:core)

    Rails.logger.info "[ContinuousBenchmark] Completed: #{results[:total_scenarios]} scenarios, " \
                      "avg score: #{results[:average_score]}, pass rate: #{results[:pass_rate]}%"

    benchmark_run = BenchmarkRun.find(results[:benchmark_run_id])
    comparator = Benchmarks::V2::Comparator.new
    comparison = comparator.compare(benchmark_run)

    if comparison[:improvements].any?
      comparator.update_baselines!(benchmark_run)
      Rails.logger.info "[ContinuousBenchmark] Baselines updated for: #{comparison[:improvements].join(', ')}"
    end

    results
  rescue => e
    Rails.logger.error "[ContinuousBenchmark] Failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
  end
end
