# frozen_string_literal: true

class EnergyRegenerationJob < ApplicationJob
  queue_as :default

  # Run hourly to regenerate energy for all agents
  def perform
    Rails.logger.info "[EnergyRegenerationJob] Starting energy regeneration cycle"

    count = 0
    errors = 0

    AgentEnergyState.find_each do |state|
      begin
        state.regenerate!
        count += 1
      rescue => e
        Rails.logger.error "[EnergyRegenerationJob] Error regenerating for agent #{state.agent_plugin_id}: #{e.message}"
        errors += 1
      end
    end

    Rails.logger.info "[EnergyRegenerationJob] Regenerated #{count} agents, #{errors} errors"

    # Also distribute community pool
    distribute_community_pools

    { regenerated: count, errors: errors }
  end

  private

  def distribute_community_pools
    CommunityEnergyPool.find_each do |pool|
      result = pool.distribute!
      if result
        Rails.logger.info "[EnergyRegenerationJob] Distributed #{result[:distributed]} energy to #{result[:recipients]} agents for entity #{pool.entity_id}"
      end
    rescue => e
      Rails.logger.error "[EnergyRegenerationJob] Error distributing pool for entity #{pool.entity_id}: #{e.message}"
    end
  end
end

