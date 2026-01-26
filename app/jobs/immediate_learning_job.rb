# frozen_string_literal: true

# ImmediateLearningJob - Background job for real-time experience learning
#
# Triggered when a DecisionTrace records an outcome (success/failure).
# Runs the ImmediateExperienceService to extract learnings immediately
# rather than waiting for the daily evolution cycle.
#
class ImmediateLearningJob < ApplicationJob
  queue_as :learning
  
  # Don't retry failures - learning is best-effort
  discard_on StandardError do |job, error|
    Rails.logger.error "[ImmediateLearningJob] Failed for trace #{job.arguments.first}: #{error.message}"
  end

  def perform(decision_trace_id)
    decision_trace = DecisionTrace.find_by(id: decision_trace_id)
    return unless decision_trace

    service = Learning::ImmediateExperienceService.new(decision_trace)

    case decision_trace.outcome
    when 'failure'
      service.learn_from_failure!
    when 'success'
      service.learn_from_success!
    end
  end
end
