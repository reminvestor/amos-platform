# frozen_string_literal: true

# DeployTracker - Detects new deployments and triggers post-deploy benchmarks
#
# On boot, compares the current git commit to the last known deployed commit.
# If different, records the deployment and enqueues a benchmark run.
#
Rails.application.config.after_initialize do
  next unless Rails.env.production?
  next if defined?(Rails::Console) || $PROGRAM_NAME.include?("rake")

  begin
    current_commit = ENV["GIT_COMMIT"] || `git rev-parse --short HEAD 2>/dev/null`.strip
    next if current_commit.blank?

    last_commit = Rails.cache.read("deploy_tracker:last_commit")

    if last_commit != current_commit
      Rails.cache.write("deploy_tracker:last_commit", current_commit)
      Rails.cache.write("deploy_tracker:deployed_at", Time.current.iso8601)

      Rails.logger.info "[DeployTracker] New deployment detected: #{last_commit || 'initial'} -> #{current_commit}"

      if last_commit.present?
        PostDeployBenchmarkJob.perform_later(current_commit, last_commit)
      else
        Rails.logger.info "[DeployTracker] First boot, setting baseline commit. No benchmark triggered."
      end
    end
  rescue => e
    Rails.logger.warn "[DeployTracker] Failed to check deployment: #{e.message}"
  end
end
