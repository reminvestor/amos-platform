# frozen_string_literal: true

# Cleanup expired agent scratchpad entries
# This job should be run daily via scheduled task
class CleanupAgentScratchpadJob < ApplicationJob
  queue_as :maintenance

  def perform
    Rails.logger.info "[CleanupAgentScratchpadJob] Starting scratchpad cleanup..."
    
    count = AgentScratchpad.cleanup_expired!
    
    Rails.logger.info "[CleanupAgentScratchpadJob] Completed. Removed #{count} expired entries."
    
    { cleaned_up: count }
  end
end

