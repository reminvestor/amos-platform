# frozen_string_literal: true

class AgentDecisionBoundaryUpdateJob < ApplicationJob
  queue_as :agents

  # Run daily to update decision boundaries based on recent outcomes
  def perform
    Rails.logger.info "[AgentDecisionBoundaryUpdateJob] Starting daily decision boundary update"

    stats = { agents_processed: 0, boundaries_updated: 0, thresholds_changed: 0 }

    AgentPlugin.available.includes(:decision_boundary).find_each do |agent|
      begin
        boundary = agent.decision_boundary
        next unless boundary

        old_threshold = boundary.current_threshold

        # Update based on recent outcomes
        boundary.update_from_recent_outcomes

        stats[:boundaries_updated] += 1

        if (boundary.current_threshold - old_threshold).abs > 2
          stats[:thresholds_changed] += 1
          Rails.logger.info "[AgentDecisionBoundaryUpdateJob] Agent #{agent.name} threshold changed: #{old_threshold.round(1)} -> #{boundary.current_threshold.round(1)}"
        end

        stats[:agents_processed] += 1
      rescue => e
        Rails.logger.error "[AgentDecisionBoundaryUpdateJob] Error processing agent #{agent.id}: #{e.message}"
      end
    end

    Rails.logger.info "[AgentDecisionBoundaryUpdateJob] Completed: #{stats.to_json}"
    stats
  end
end

