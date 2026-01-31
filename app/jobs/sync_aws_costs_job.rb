# frozen_string_literal: true

# SyncAwsCostsJob
#
# Daily job to sync AWS costs from Cost Explorer API.
# This ensures our platform economics are based on real AWS costs,
# not just estimates.
#
# Schedule: Run daily at 6 AM UTC (after AWS has processed yesterday's costs)
#
# Usage:
#   SyncAwsCostsJob.perform_later
#   SyncAwsCostsJob.perform_later(sync_monthly: true, year: 2026, month: 1)
#
class SyncAwsCostsJob < ApplicationJob
  queue_as :low

  # Retry up to 3 times with exponential backoff
  retry_on StandardError, attempts: 3, wait: :exponentially_longer

  def perform(sync_monthly: false, year: nil, month: nil)
    Rails.logger.info "[SyncAwsCosts] Starting AWS cost sync..."

    if sync_monthly && year && month
      # Full month reconciliation
      result = sync_monthly_costs(year, month)
    else
      # Daily sync (yesterday's costs)
      result = sync_daily_costs
    end

    if result[:success]
      Rails.logger.info "[SyncAwsCosts] ✅ Sync completed: #{result[:message]}"
      
      # Notify admins if significant variance detected
      check_cost_variance(result)
    else
      Rails.logger.error "[SyncAwsCosts] ❌ Sync failed: #{result[:error]}"
      
      # Create system notification for failed sync
      create_failure_notification(result[:error])
    end

    result
  end

  private

  def sync_daily_costs
    Rails.logger.info "[SyncAwsCosts] Syncing yesterday's costs..."
    
    result = Aws::CostExplorerSyncService.sync_daily!
    
    if result[:success]
      {
        success: true,
        message: "Synced #{result[:services_synced]} services, total: $#{result[:total_synced]}",
        total: result[:total_synced],
        period: result[:period]
      }
    else
      { success: false, error: result[:error] }
    end
  end

  def sync_monthly_costs(year, month)
    Rails.logger.info "[SyncAwsCosts] Syncing monthly costs for #{year}-#{month}..."
    
    result = Aws::CostExplorerSyncService.sync_monthly!(year: year, month: month)
    
    if result[:success]
      {
        success: true,
        message: "Synced monthly costs for #{year}-#{month}, total: $#{result[:total_synced]}",
        total: result[:total_synced],
        period: "#{year}-#{month}"
      }
    else
      { success: false, error: result[:error] }
    end
  end

  def check_cost_variance(result)
    # Get reconciliation report for the last 30 days
    report = Aws::CostExplorerSyncService.reconciliation_report(
      start_date: 30.days.ago.to_date,
      end_date: Date.yesterday
    )

    return unless report.present?

    # Check for significant variance (>20%)
    total_variance = report[:total_actual] - report[:total_estimated]
    variance_pct = report[:total_estimated] > 0 ? 
                   (total_variance / report[:total_estimated] * 100).abs : 0

    if variance_pct > 20
      Rails.logger.warn "[SyncAwsCosts] ⚠️ Significant cost variance detected: #{variance_pct.round(1)}%"
      
      SystemNotification.create!(
        notification_type: 'cost_variance',
        severity: 'warning',
        title: "AWS Cost Variance Alert",
        message: "Estimated costs differ from actual by #{variance_pct.round(1)}%. " \
                 "Estimated: $#{report[:total_estimated]}, Actual: $#{report[:total_actual]}",
        metadata: {
          total_estimated: report[:total_estimated],
          total_actual: report[:total_actual],
          variance_percentage: variance_pct.round(2),
          period: report[:period]
        }
      )
    end
  rescue => e
    Rails.logger.warn "[SyncAwsCosts] Variance check failed: #{e.message}"
  end

  def create_failure_notification(error)
    SystemNotification.create!(
      notification_type: 'job_failure',
      severity: 'error',
      title: "AWS Cost Sync Failed",
      message: "Failed to sync AWS costs: #{error}. " \
               "Platform economics may be based on estimates only.",
      metadata: { error: error, job: 'SyncAwsCostsJob' }
    )
  rescue => e
    Rails.logger.error "[SyncAwsCosts] Failed to create notification: #{e.message}"
  end
end
