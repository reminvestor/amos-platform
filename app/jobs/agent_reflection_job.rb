# frozen_string_literal: true

# AgentReflectionJob
#
# Background job for running agent reflection cycles.
# Should be scheduled to run periodically (daily or weekly) for each active agent.
#
# Usage:
#   AgentReflectionJob.perform_later(agent.id)
#   AgentReflectionJob.perform_all_active  # Run for all active agents
#
class AgentReflectionJob < ApplicationJob
  queue_as :low_priority
  
  # Don't retry reflection - it's not critical
  discard_on StandardError
  discard_on ActiveRecord::RecordNotFound

  def perform(agent_id)
    agent = AgentPlugin.find(agent_id)
    
    # Skip if agent is not active or on probation
    unless agent.status.in?(%w[active probation])
      Rails.logger.info "[AgentReflectionJob] Skipping #{agent.name} - status: #{agent.status}"
      return
    end
    
    Rails.logger.info "[AgentReflectionJob] Starting reflection for: #{agent.name}"
    
    service = AgentReflectionService.new(agent)
    result = service.run_reflection_cycle!
    
    if result[:success]
      Rails.logger.info "[AgentReflectionJob] Reflection complete for #{agent.name}"
      Rails.logger.info "[AgentReflectionJob] Insights: #{result[:insights].to_json}"
    else
      Rails.logger.info "[AgentReflectionJob] Reflection skipped for #{agent.name}: #{result[:reason]}"
    end
  end

  # Class method to queue reflection for all active agents
  def self.perform_all_active
    agents = AgentPlugin.where(status: %w[active probation])
    
    Rails.logger.info "[AgentReflectionJob] Queueing reflection for #{agents.count} agents"
    
    agents.find_each do |agent|
      AgentReflectionJob.perform_later(agent.id)
    end
    
    agents.count
  end
end

