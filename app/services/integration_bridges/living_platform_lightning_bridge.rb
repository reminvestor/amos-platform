# frozen_string_literal: true

module IntegrationBridges
  # LivingPlatformLightningBridge - Connects Living Platform to Agent Lightning
  #
  # When the Living Platform generates improvement goals for agents,
  # this bridge can trigger Agent Lightning training to optimize prompts.
  #
  class LivingPlatformLightningBridge
    attr_reader :entity

    def initialize(entity)
      @entity = entity
    end

    # Process a goal and trigger training if appropriate
    def process_goal(goal)
      return unless goal.goal_type == 'improvement'
      return unless goal.agent_plugin.present?

      agent = goal.agent_plugin
      config = agent_lightning_config

      return unless config&.enabled?
      return unless has_enough_traces?(agent)

      # Trigger training
      result = trigger_training_for_agent(agent, goal)

      # Update goal with training info
      if result[:success]
        goal.update!(
          metadata: (goal.metadata || {}).merge(
            agent_lightning_triggered: true,
            training_job_id: result[:job_id]
          )
        )
        Rails.logger.info "[LivingPlatformLightningBridge] Triggered training for #{agent.name}"
      end

      result
    end

    # Process all pending improvement goals
    def process_pending_improvement_goals
      goals = AgentGoal.where(entity: entity, goal_type: 'improvement', status: 'pending')
        .where.not(agent_plugin_id: nil)
        .limit(10)

      results = goals.map do |goal|
        { goal_id: goal.id, result: process_goal(goal) }
      end

      {
        processed: results.count { |r| r[:result].present? },
        triggered_training: results.count { |r| r.dig(:result, :success) },
        results: results
      }
    end

    # Check if an agent should be trained based on Living Platform signals
    def should_train?(agent)
      return false unless agent_lightning_config&.enabled?
      return false unless has_enough_traces?(agent)

      # Check if agent has recent poor performance
      recent_executions = agent.agent_plugin_executions
        .where('created_at > ?', 7.days.ago)

      total = recent_executions.count
      return false if total < 10  # Not enough data

      failures = recent_executions.where(status: 'failed').count
      failure_rate = failures.to_f / total

      # Train if failure rate is high or has improvement goals
      failure_rate > 0.2 || has_improvement_goal?(agent)
    end

    private

    def agent_lightning_config
      @config ||= entity.agent_lightning_config
    end

    def has_enough_traces?(agent)
      min_traces = agent_lightning_config&.min_traces_for_training || 50

      entity.agent_lightning_traces
        .where(agent_plugin: agent)
        .completed
        .where(included_in_training: false)
        .count >= min_traces
    end

    def has_improvement_goal?(agent)
      AgentGoal.where(
        entity: entity,
        agent_plugin: agent,
        goal_type: 'improvement',
        status: %w[pending scheduled in_progress]
      ).exists?
    end

    def trigger_training_for_agent(agent, goal)
      service = AgentLightningTrainingService.new(entity)

      # Get traces for this specific agent
      traces = entity.agent_lightning_traces
        .where(agent_plugin: agent)
        .completed
        .with_reward
        .where(included_in_training: false)
        .limit(500)

      if traces.count < 10
        return { success: false, message: "Not enough traces for training" }
      end

      # Execute training
      service.execute_training(traces)
    rescue => e
      Rails.logger.error "[LivingPlatformLightningBridge] Training failed: #{e.message}"
      { success: false, error: e.message }
    end
  end
end


