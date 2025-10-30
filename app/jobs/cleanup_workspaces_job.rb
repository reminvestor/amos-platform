class CleanupWorkspacesJob < ApplicationJob
  queue_as :maintenance

  def perform
    Rails.logger.info "🧹 Starting workspace cleanup..."

    # Cleanup workspaces older than 24 hours
    count = Agents::WorkspaceManager.cleanup_old_workspaces!(older_than: 24.hours)

    Rails.logger.info "✅ Cleaned up #{count} old workspaces"

    # Log disk usage
    total_usage = Agents::WorkspaceManager.total_disk_usage
    usage_mb = (total_usage / 1.megabyte).round(2)
    Rails.logger.info "💾 Total workspace disk usage: #{usage_mb} MB"
  rescue => e
    Rails.logger.error "Workspace cleanup failed: #{e.message}"
  end
end
