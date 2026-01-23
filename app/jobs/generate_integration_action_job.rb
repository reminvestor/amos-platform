# frozen_string_literal: true

# GenerateIntegrationActionJob - Async action generation for new operations
#
# Called automatically when an IntegrationOperation is created (if auto-generation enabled).
# Can also be called manually to regenerate actions.
#
class GenerateIntegrationActionJob < ApplicationJob
  queue_as :default

  def perform(operation_id, options = {})
    operation = IntegrationOperation.find_by(id: operation_id)
    return unless operation

    Rails.logger.info "[GenerateIntegrationActionJob] Generating action for: #{operation.operation_id}"

    result = Integrations::ActionGeneratorService.generate_for_operation(
      operation,
      options.merge(auto_activate: false)  # Create as draft by default
    )

    if result[:success]
      Rails.logger.info "[GenerateIntegrationActionJob] ✅ Created action: #{result[:action].slug}"
    else
      Rails.logger.warn "[GenerateIntegrationActionJob] ⚠️ Skipped: #{result[:error]}"
    end
  rescue => e
    Rails.logger.error "[GenerateIntegrationActionJob] ❌ Failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end

