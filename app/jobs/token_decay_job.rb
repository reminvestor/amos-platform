# frozen_string_literal: true

# Scheduled job to apply daily decay to all token stakes
# Should be run once per day, typically early morning
class TokenDecayJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "🔄 TokenDecayJob starting..."
    
    result = TokenEconomyService.apply_daily_decay!
    
    Rails.logger.info "✅ TokenDecayJob complete: " \
                      "#{result[:stakes_processed]} stakes processed, " \
                      "#{result[:total_decayed].round(2)} tokens decayed"
    
    # Record metrics for monitoring
    SystemNotification.create(
      notification_type: 'token_economy',
      severity: 'info',
      title: 'Daily token decay completed',
      message: "Processed #{result[:stakes_processed]} stakes, " \
               "decayed #{result[:total_decayed].round(2)} tokens",
      metadata: result
    ) if result[:stakes_processed] > 0
    
    result
  rescue StandardError => e
    Rails.logger.error "❌ TokenDecayJob failed: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    
    SystemNotification.create(
      notification_type: 'token_economy',
      severity: 'error',
      title: 'Token decay job failed',
      message: e.message,
      metadata: { error: e.class.name, backtrace: e.backtrace.first(5) }
    )
    
    raise e
  end
end
