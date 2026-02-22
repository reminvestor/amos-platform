# frozen_string_literal: true

# PostDeployBenchmarkJob - Runs core benchmark suite after a new deployment
#
# Triggered automatically by the deploy tracker initializer when a new
# git commit is detected on boot. Runs the core scenario suite (~8 scenarios)
# and compares to baseline, emitting signals for any regressions.
#
class PostDeployBenchmarkJob < ApplicationJob
  queue_as :living_platform

  def perform(current_commit, previous_commit)
    Rails.logger.info "[PostDeployBenchmark] Starting post-deploy benchmark for #{current_commit} (prev: #{previous_commit})"

    entity = Entity.find_by(slug: "amos-labs") || Entity.first
    user = entity&.users&.first
    return unless entity && user

    runner = Benchmarks::V2::Runner.new(
      entity: entity,
      user: user,
      run_type: "v2_benchmark"
    )

    results = runner.run_suite(:core)

    Rails.logger.info "[PostDeployBenchmark] Completed: #{results[:total_scenarios]} scenarios, " \
                      "avg score: #{results[:average_score]}, pass rate: #{results[:pass_rate]}%"

    benchmark_run = BenchmarkRun.find(results[:benchmark_run_id])
    comparator = Benchmarks::V2::Comparator.new
    comparison = comparator.compare(benchmark_run)

    if comparison[:regressions].any?
      Rails.logger.warn "[PostDeployBenchmark] REGRESSIONS DETECTED: #{comparison[:regressions].join(', ')}"

      AmosSignal.record!(
        entity: entity,
        signal_type: "platform_improvement",
        source: "platform_health_scanner",
        strength: 0.9,
        summary: "Post-deploy benchmark regression: #{comparison[:regressions].size} scenario(s) degraded",
        data: {
          "check_name" => "post_deploy_benchmark",
          "severity" => "high",
          "scope" => "platform",
          "git_commit" => current_commit,
          "previous_commit" => previous_commit,
          "regressions" => comparison[:regressions],
          "scorecard" => comparison[:scorecard]
        }
      )
    end

    if comparison[:improvements].any?
      Rails.logger.info "[PostDeployBenchmark] Improvements: #{comparison[:improvements].join(', ')}"
      comparator.update_baselines!(benchmark_run)
    end

    results
  rescue => e
    Rails.logger.error "[PostDeployBenchmark] Failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    raise
  end
end
