# frozen_string_literal: true

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           ⚠️ DEPRECATED ⚠️                                  ║
# ╠════════════════════════════════════════════════════════════════════════════╣
# ║ This file is DEPRECATED as of 2026-01-24.                                   ║
# ║                                                                             ║
# ║ With the Plugin Injection architecture, energy tracking is not needed:      ║
# ║ - Amos handles all tasks directly                                           ║
# ║ - No agent resource management                                              ║
# ║ - No execution-based energy consumption                                     ║
# ║                                                                             ║
# ║ REPLACEMENT:                                                                ║
# ║ - LoadoutMetric - for tracking loadout performance metrics                   ║
# ║                                                                             ║
# ║ DO NOT USE THIS FILE FOR NEW CODE.                                          ║
# ╚════════════════════════════════════════════════════════════════════════════╝

module Collaboration
  class EnergyTracker
    def initialize(agent_plugin)
      @agent = agent_plugin
      @pricer = DynamicEnergyPricer.new
    end

    # ============================================
    # EXECUTION LIFECYCLE
    # ============================================

    def on_execution_start(execution)
      # Ensure energy state exists
      ensure_energy_state!

      # Record start time and initial confidence in input_context
      # AgentPluginExecution uses input_context, not metadata
      begin
        current_context = execution.input_context || {}
        current_context['energy_tracking'] = {
          'start_energy' => @agent.current_energy,
          'started_at' => Time.current.iso8601
        }
        execution.update!(input_context: current_context)
      rescue => e
        Rails.logger.warn "[EnergyTracker] Could not update execution context: #{e.message}"
      end

      Rails.logger.info "[EnergyTracker] 🔋 Agent #{@agent.name} starting execution with #{@agent.current_energy.round(1)} energy"
    end

    def on_execution_complete(execution, result)
      return unless @agent.energy_state

      # Calculate reward
      quality = extract_quality_score(result)
      reward = @pricer.task_completion_reward(execution)

      # Earn energy
      @agent.energy_state.earn!(
        reward,
        reason: 'task_completion',
        execution: execution
      )

      # Update stats
      @agent.energy_state.update_stats!(success: true, quality: quality)

      # Update capability belief
      task_type = classify_task_type(execution)
      @agent.update_capability_belief!(
        task_type: task_type,
        success: true,
        quality: quality
      )

      # Learn from decision
      learn_from_execution(execution, success: true, quality: quality)

      # Update Elo rating
      task_difficulty = estimate_task_difficulty(execution)
      @agent.energy_state.update_elo!(task_difficulty, 1.0)

      Rails.logger.info "[EnergyTracker] ✅ Agent #{@agent.name} earned #{reward.round(1)} energy. New balance: #{@agent.current_energy.round(1)}"

      # Record in execution metadata
      update_execution_energy_metadata(execution, reward: reward, quality: quality)
    end

    def on_execution_failed(execution, error)
      return unless @agent.energy_state

      # Calculate penalty
      penalty = @pricer.failure_penalty(@agent, execution)

      # Apply penalty
      @agent.energy_state.penalize!(
        penalty,
        reason: 'task_failure',
        execution: execution
      )

      # Update stats
      @agent.energy_state.update_stats!(success: false, quality: 0.0)

      # Update capability belief
      task_type = classify_task_type(execution)
      @agent.update_capability_belief!(
        task_type: task_type,
        success: false,
        quality: 0.0
      )

      # Learn from decision
      learn_from_execution(execution, success: false, quality: 0.0)

      # Update Elo rating
      task_difficulty = estimate_task_difficulty(execution)
      @agent.energy_state.update_elo!(task_difficulty, 0.0)

      Rails.logger.info "[EnergyTracker] ❌ Agent #{@agent.name} penalized #{penalty.round(1)} energy. New balance: #{@agent.current_energy.round(1)}"

      # Record in execution metadata
      update_execution_energy_metadata(execution, penalty: penalty, error: error.message)

      # Check if agent needs school
      if @agent.current_energy <= 0
        Rails.logger.warn "[EnergyTracker] 🎓 Agent #{@agent.name} has 0 energy - scheduling school enrollment"
        AgentSchoolEnrollmentJob.perform_later(@agent.id)
      end
    end

    # ============================================
    # COLLABORATION
    # ============================================

    def on_collaboration_requested(request)
      return unless @agent.energy_state

      cost = request.energy_cost

      begin
        @agent.energy_state.spend!(
          cost,
          reason: "collaboration_#{request.request_type}",
          request: request
        )

        Rails.logger.info "[EnergyTracker] 💬 Agent #{@agent.name} spent #{cost.round(1)} energy asking for help"
        true
      rescue InsufficientEnergyError => e
        Rails.logger.warn "[EnergyTracker] ⚠️ Agent #{@agent.name} has insufficient energy for collaboration"
        false
      end
    end

    def on_collaboration_completed(request)
      return unless request.helper_agent&.energy_state

      reward = @pricer.helper_reward(
        request.request_type,
        quality_rating: request.quality_rating,
        was_helpful: request.was_helpful,
        response_time_ms: request.response_time_ms
      )

      request.helper_agent.energy_state.earn!(
        reward,
        reason: 'helped_agent',
        request: request
      )

      # Update helper's stats
      request.helper_agent.energy_state.update!(
        help_given: request.helper_agent.energy_state.help_given + 1
      )

      # Update requester's stats
      if @agent.energy_state
        @agent.energy_state.update!(
          help_received: @agent.energy_state.help_received + 1
        )
      end

      Rails.logger.info "[EnergyTracker] 🤝 Agent #{request.helper_agent.name} earned #{reward.round(1)} energy for helping"
    end

    # ============================================
    # DECISION SUPPORT
    # ============================================

    def should_ask_for_help?(task_description)
      # Estimate confidence for this task
      confidence = @agent.estimate_confidence(task_description)

      # Check decision boundary
      decision = @agent.should_ask_for_help?(confidence)

      Rails.logger.info "[EnergyTracker] 🤔 Agent #{@agent.name} confidence: #{confidence.round(1)}%, threshold: #{decision[:sampled_threshold].round(1)}%"
      Rails.logger.info "[EnergyTracker] 📊 Decision: #{decision[:should_ask] ? 'ASK FOR HELP' : 'TRY SOLO'}"

      decision
    end

    def find_best_helper(task_description, required_capabilities: [])
      # Use the router to find the best helper
      # Note: router is not used in current implementation but kept for future expansion
      # router = IreplaceabilityAwareRouter.new(entity: @agent.entity)

      # Filter out self
      candidates = AgentPlugin.available
        .where(entity: @agent.entity)
        .where.not(id: @agent.id)
        .where('agent_energy_states.current_energy >= ?', 30)
        .joins(:energy_state)

      # Score candidates based on relationship and capability
      scored = candidates.map do |candidate|
        relationship = AgentRelationship.find_by(requester: @agent, helper: candidate)

        {
          agent: candidate,
          capability_score: candidate.capability_for_task(task_description),
          relationship_score: relationship&.compatibility_score || 0.5,
          availability: candidate.availability_score,
          cost: @pricer.calculate_collaboration_cost(:subtask, @agent, candidate)
        }
      end

      # Sort by combined score (capability + relationship - cost normalized)
      scored.sort_by do |s|
        -(s[:capability_score] * 0.4 + s[:relationship_score] * 0.3 + s[:availability] * 0.2 - s[:cost] / 30.0 * 0.1)
      end.first
    end

    private

    def ensure_energy_state!
      @agent.ensure_energy_state!
      @agent.ensure_decision_boundary!
    end

    def extract_quality_score(result)
      # Try to extract quality from result
      if result.is_a?(Hash)
        return result[:quality_score] || result['quality_score'] if result[:quality_score] || result['quality_score']
      end

      # Default quality based on result presence
      result.present? ? 0.7 : 0.3
    end

    def classify_task_type(execution)
      # Use input_context instead of input (which doesn't exist on AgentPluginExecution)
      task = execution.input_context&.dig('task_description') || ''
      task = task.to_s.downcase

      if task.include?('analyze') || task.include?('analysis')
        'analysis'
      elsif task.include?('create') || task.include?('generate') || task.include?('build')
        'creation'
      elsif task.include?('research') || task.include?('find') || task.include?('search')
        'research'
      elsif task.include?('integrate') || task.include?('api') || task.include?('connect')
        'integration'
      elsif task.include?('email') || task.include?('message') || task.include?('send')
        'communication'
      elsif task.include?('report') || task.include?('visualiz') || task.include?('chart')
        'reporting'
      else
        'general'
      end
    end

    def estimate_task_difficulty(execution)
      # Estimate difficulty based on various factors
      difficulty = 1000  # Base Elo-style difficulty

      # Longer tasks are harder
      if execution.duration_ms && execution.duration_ms > 60_000
        difficulty += 200
      end

      # More tool usage indicates complexity
      # Use input_context instead of metadata (which doesn't exist on AgentPluginExecution)
      tools_used = execution.input_context&.dig('tools_used')&.size || 0
      difficulty += tools_used * 50

      difficulty
    end

    def learn_from_execution(execution, success:, quality:)
      return unless @agent.decision_boundary

      # Check if agent asked for help during this execution
      asked_for_help = @agent.collaboration_requests_made
        .where(agent_plugin_execution: execution)
        .exists?

      # Get confidence at start from input_context
      confidence = execution.input_context&.dig('energy_tracking', 'confidence_at_start') || 50.0

      # Update decision boundary
      @agent.decision_boundary.learn_from_outcome!(
        confidence: confidence,
        asked_for_help: asked_for_help,
        success: success,
        quality: quality
      )
    end

    def update_execution_energy_metadata(execution, data)
      # Use input_context instead of metadata
      begin
        current_context = execution.input_context || {}
        energy_tracking = current_context['energy_tracking'] || {}
        energy_tracking.merge!(data.stringify_keys)
        energy_tracking['end_energy'] = @agent.current_energy
        energy_tracking['ended_at'] = Time.current.iso8601
        current_context['energy_tracking'] = energy_tracking

        execution.update!(input_context: current_context)
      rescue => e
        Rails.logger.warn "[EnergyTracker] Could not update execution energy metadata: #{e.message}"
      end
    end
  end
end

