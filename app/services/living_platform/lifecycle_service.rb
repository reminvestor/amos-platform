# frozen_string_literal: true

module LivingPlatform
  # LifecycleService - Agent Birth, Maturation, and Retirement
  #
  # Manages the complete lifecycle of agents from creation to retirement:
  # - Birth: Creating new agents based on detected needs
  # - Training: Integrating with Agent School for education
  # - Maturation: Graduating agents to full operation
  # - Retirement: Gracefully deprecating obsolete agents
  # - Resurrection: Bringing back retired agents if needed
  #
  # Integration:
  # - Uses Collaboration::AgentSchool for training
  # - Uses DesireEngine for goal-driven births
  # - Uses EvolutionService for performance analysis
  # - Creates AgentLifecycleEvent records
  # - Preserves knowledge via GlobalKnowledgeArchive
  #
  class LifecycleService
    attr_reader :entity

    # Configuration
    INACTIVITY_THRESHOLD_DAYS = 90
    FAILURE_RATE_THRESHOLD = 0.7  # 70% failure rate triggers retirement consideration
    MIN_EXECUTIONS_FOR_EVALUATION = 50
    TRAINING_GRADUATION_THRESHOLD = 0.75  # 75% success rate to graduate

    def initialize(entity)
      @entity = entity
      @evolution_service = Agents::EvolutionService.new(entity: entity)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # BIRTH
    # Create new agents based on detected needs
    # ═══════════════════════════════════════════════════════════════════════════

    def birth_agent(need:, parent_agents: [], trigger: 'desire_engine', goal: nil)
      Rails.logger.info "[Lifecycle] Birthing new agent for: #{need[:description]}"
      
      # Design the agent
      design = design_agent_from_need(need, parent_agents)
      
      # Create the agent
      agent = AgentPlugin.create!(
        entity: entity,
        slug: design[:slug],
        name: design[:name],
        status: 'draft',
        lifecycle_stage: 'training',
        author_type: 'amos',
        system_prompt: { 'prompt' => design[:system_prompt] },
        capabilities_definition: { 'capabilities' => design[:capabilities] },
        generation: calculate_generation(parent_agents),
        birth_reason: need[:description],
        parent_agent_ids: parent_agents.map(&:id),
        metadata: {
          birth_trigger: trigger,
          birth_need: need,
          design: design
        }
      )
      
      # Assign tools
      design[:tools].each do |tool_name|
        agent.agent_tools.create!(tool_name: tool_name)
      end
      
      # Record lifecycle event
      AgentLifecycleEvent.record_birth(
        agent,
        trigger: trigger,
        goal: goal,
        parent_agents: parent_agents,
        reason: need[:description]
      )
      
      # Start training
      start_training(agent)
      
      Rails.logger.info "[Lifecycle] Agent #{agent.name} born (generation #{agent.generation})"
      
      agent
    end

    def design_agent_from_need(need, parent_agents)
      # Use AI to design the agent
      prompt = build_agent_design_prompt(need, parent_agents)
      
      begin
        response = BedrockService.new(entity: entity).quick_completion(prompt)
        design = JSON.parse(response)
        
        {
          slug: design['slug'] || need[:description].parameterize.underscore.truncate(50),
          name: design['name'] || need[:description].truncate(50),
          system_prompt: design['system_prompt'] || build_default_system_prompt(need),
          capabilities: design['capabilities'] || [],
          tools: design['tools'] || suggest_tools_for_need(need)
        }
      rescue => e
        Rails.logger.warn "[Lifecycle] AI design failed: #{e.message}, using defaults"
        
        {
          slug: need[:description].parameterize.underscore.truncate(50),
          name: need[:description].truncate(50),
          system_prompt: build_default_system_prompt(need),
          capabilities: [],
          tools: suggest_tools_for_need(need)
        }
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # TRAINING
    # Integrate with Agent School for agent education
    # ═══════════════════════════════════════════════════════════════════════════

    def start_training(agent)
      Rails.logger.info "[Lifecycle] Starting training for #{agent.name}"
      
      # Create training tasks
      training_tasks = generate_training_tasks(agent)
      
      training_tasks.each do |task_spec|
        ScheduledAgentTask.create!(
          entity: entity,
          user: entity.users.first,
          agent_plugin: agent,
          name: "Training: #{task_spec[:name]}",
          description: task_spec[:description],
          task_type: 'custom',
          prompt: task_spec[:prompt],
          schedule_type: 'once',
          next_run_at: task_spec[:scheduled_for] || 1.hour.from_now,
          enabled: true,
          execution_mode: 'agent_only'
        )
      end
      
      # Update agent status
      agent.update!(lifecycle_stage: 'training')
      
      # Record event
      AgentLifecycleEvent.create!(
        entity: entity,
        agent_plugin: agent,
        event_type: 'training_started',
        description: "Training started with #{training_tasks.count} modules",
        triggered_by: 'lifecycle_service',
        event_data: { training_tasks: training_tasks.count }
      )
    end

    def evaluate_training_completion(agent)
      return false unless agent.lifecycle_stage == 'training'
      
      # Get training performance
      executions = agent.agent_plugin_executions.where('created_at > ?', 7.days.ago)
      
      return false if executions.count < 10  # Need minimum data
      
      completed = executions.where(status: 'completed').count
      total = executions.count
      success_rate = total > 0 ? (completed.to_f / total) : 0
      
      if success_rate >= TRAINING_GRADUATION_THRESHOLD
        mature_agent(agent)
        true
      else
        # Extend training or trigger Agent School
        if success_rate < 0.5
          # Agent is struggling, enroll in Agent School
          school = Collaboration::AgentSchool.new
          school.enroll(agent) if agent.current_energy.to_i <= 0
        end
        false
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MATURATION
    # Graduate agents from training to full operation
    # ═══════════════════════════════════════════════════════════════════════════

    def mature_agent(agent)
      Rails.logger.info "[Lifecycle] Maturing agent #{agent.name}"
      
      agent.update!(
        lifecycle_stage: 'active',
        status: 'active'
      )
      
      # Record event
      AgentLifecycleEvent.record_maturation(agent, trigger: 'lifecycle_service')
      
      # Notify entity
      create_maturation_notification(agent)
      
      agent
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # RETIREMENT EVALUATION
    # Evaluate agents for potential retirement
    # ═══════════════════════════════════════════════════════════════════════════

    def evaluate_for_retirement(agent)
      metrics = gather_retirement_metrics(agent)
      
      reasons = []
      
      # Reason 1: Inactivity
      if metrics[:days_inactive] >= INACTIVITY_THRESHOLD_DAYS
        reasons << {
          type: :inactivity,
          description: "No activity for #{metrics[:days_inactive]} days",
          severity: :medium
        }
      end
      
      # Reason 2: Consistent failure
      if metrics[:total_executions] >= MIN_EXECUTIONS_FOR_EVALUATION
        if metrics[:failure_rate] >= FAILURE_RATE_THRESHOLD
          reasons << {
            type: :poor_performance,
            description: "Failure rate of #{(metrics[:failure_rate] * 100).round}%",
            severity: :high
          }
        end
      end
      
      # Reason 3: Superseded by better agent
      better_alternative = find_better_alternative(agent)
      if better_alternative
        reasons << {
          type: :superseded,
          description: "Better alternative available: #{better_alternative.name}",
          successor: better_alternative.slug,
          severity: :low
        }
      end
      
      # Reason 4: No longer needed
      if metrics[:total_executions] == 0 && metrics[:days_since_creation] > 30
        reasons << {
          type: :never_used,
          description: "Never used since creation #{metrics[:days_since_creation]} days ago",
          severity: :medium
        }
      end
      
      {
        agent: agent.slug,
        should_retire: reasons.any? { |r| r[:severity] == :high } || reasons.count >= 2,
        reasons: reasons,
        metrics: metrics
      }
    end

    def evaluate_all_agents
      entity.agent_plugins.where(status: 'active').map do |agent|
        evaluate_for_retirement(agent)
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # RETIREMENT
    # Gracefully retire obsolete agents
    # ═══════════════════════════════════════════════════════════════════════════

    def retire_agent(agent, reasons:, trigger: 'lifecycle_service', goal: nil)
      Rails.logger.info "[Lifecycle] Retiring agent #{agent.name}. Reasons: #{reasons.map { |r| r[:type] }.join(', ')}"
      
      # 1. Preserve knowledge before retirement
      preserved_knowledge = preserve_agent_knowledge(agent)
      
      # 2. Find successor if superseded
      successor = find_successor(agent, reasons)
      
      # 3. Reassign pending work
      reassigned = reassign_pending_work(agent, successor)
      
      # 4. Record final metrics
      final_metrics = gather_retirement_metrics(agent)
      
      # 5. Record lifecycle event
      AgentLifecycleEvent.record_retirement(
        agent,
        trigger: trigger,
        goal: goal,
        successor: successor,
        reason: reasons.map { |r| r[:description] }.join('; ')
      )
      
      # 6. Update agent status
      agent.update!(
        status: 'retired',
        lifecycle_stage: 'retired',
        metadata: agent.metadata.merge(
          retired_at: Time.current,
          retirement_reasons: reasons,
          final_metrics: final_metrics,
          knowledge_preserved: preserved_knowledge.count,
          successor_slug: successor&.slug
        )
      )
      
      Rails.logger.info "[Lifecycle] Agent #{agent.name} retired. " \
                        "Knowledge preserved: #{preserved_knowledge.count}, " \
                        "Work reassigned: #{reassigned.count}"
      
      {
        agent: agent.slug,
        retired: true,
        knowledge_preserved: preserved_knowledge.count,
        successor: successor&.slug,
        work_reassigned: reassigned.count
      }
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # RESURRECTION
    # Bring back retired agents if needed
    # ═══════════════════════════════════════════════════════════════════════════

    def resurrect_agent(agent, reason:, trigger: 'user_request')
      return nil unless agent.status == 'retired'
      
      Rails.logger.info "[Lifecycle] Resurrecting agent #{agent.name}"
      
      # Restore agent
      agent.update!(
        status: 'active',
        lifecycle_stage: 'active',
        metadata: agent.metadata.merge(
          resurrected_at: Time.current,
          resurrection_reason: reason
        )
      )
      
      # Record event
      AgentLifecycleEvent.create!(
        entity: entity,
        agent_plugin: agent,
        event_type: 'resurrection',
        description: "Agent resurrected: #{reason}",
        triggered_by: trigger
      )
      
      agent
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    def calculate_generation(parent_agents)
      return 1 if parent_agents.blank?
      
      parent_generations = parent_agents.filter_map(&:generation)
      return 1 if parent_generations.empty?
      
      parent_generations.max + 1
    end

    def build_agent_design_prompt(need, parent_agents)
      parent_context = parent_agents.any? ? 
        "Learn from these parent agents: #{parent_agents.map(&:name).join(', ')}" : ""
      
      <<~PROMPT
        Design a new AI agent based on this need:
        
        Need: #{need[:description]}
        Request Count: #{need[:request_count]}
        Sample Requests: #{need[:sample_requests]&.join('; ')}
        Missing Tools: #{need[:missing_tools]&.join(', ')}
        
        #{parent_context}
        
        Design the agent with:
        1. A clear, specific system prompt
        2. Appropriate capabilities
        3. Recommended tools
        
        Respond in JSON:
        {
          "slug": "snake_case_name",
          "name": "Human Readable Name",
          "system_prompt": "Complete system prompt...",
          "capabilities": ["capability1", "capability2"],
          "tools": ["tool1", "tool2"]
        }
      PROMPT
    end

    def build_default_system_prompt(need)
      <<~PROMPT
        You are a specialized agent created to handle: #{need[:description]}
        
        Your responsibilities:
        - Understand and fulfill requests related to this area
        - Use available tools effectively
        - Ask clarifying questions when needed
        - Report results clearly
        
        Be helpful, thorough, and efficient.
      PROMPT
    end

    def suggest_tools_for_need(need)
      tools = []
      
      # Common tools
      tools << 'ask_user' if need[:description]&.include?('user')
      tools << 'get_data' if need[:description]&.match?(/get|fetch|retrieve|find/)
      tools << 'create_object' if need[:description]&.match?(/create|add|new/)
      tools << 'update_object' if need[:description]&.match?(/update|modify|change/)
      
      # Include missing tools if they exist
      (need[:missing_tools] || []).each do |tool|
        catalog = Tools::ToolCatalog.instance
        tools << tool if catalog.get_tool_definition(tool)
      end
      
      tools.uniq.first(10)
    end

    def generate_training_tasks(agent)
      [
        {
          name: 'Basic Tool Usage',
          description: 'Practice using assigned tools',
          prompt: "Practice using each of your assigned tools. Try simple operations first.",
          scheduled_for: 30.minutes.from_now
        },
        {
          name: 'Task Execution',
          description: 'Execute sample tasks',
          prompt: "Execute a sample task related to your specialty: #{agent.birth_reason}",
          scheduled_for: 1.hour.from_now
        },
        {
          name: 'Error Handling',
          description: 'Practice handling errors',
          prompt: "Practice handling potential errors. What could go wrong? How would you recover?",
          scheduled_for: 2.hours.from_now
        }
      ]
    end

    def gather_retirement_metrics(agent)
      executions = agent.agent_plugin_executions
      recent_executions = executions.where('created_at > ?', 30.days.ago)
      
      completed = recent_executions.where(status: 'completed').count
      failed = recent_executions.where(status: 'failed').count
      total = completed + failed
      
      {
        total_executions: executions.count,
        recent_executions: total,
        success_rate: total > 0 ? (completed.to_f / total) : 0,
        failure_rate: total > 0 ? (failed.to_f / total) : 0,
        last_execution_at: executions.maximum(:created_at),
        days_inactive: executions.maximum(:created_at) ? 
          ((Time.current - executions.maximum(:created_at)) / 1.day).round : 999,
        days_since_creation: ((Time.current - agent.created_at) / 1.day).round,
        generation: agent.generation,
        evolution_count: agent.evolution_count
      }
    end

    def find_better_alternative(agent)
      # Find agents with similar capabilities but better performance
      similar_agents = entity.agent_plugins
        .where(status: 'active')
        .where.not(id: agent.id)
      
      similar_agents.find do |other|
        # Simple similarity check based on tools
        my_tools = agent.agent_tools.pluck(:tool_name)
        other_tools = other.agent_tools.pluck(:tool_name)
        
        overlap = (my_tools & other_tools).count
        next false if overlap < my_tools.count * 0.7  # 70% tool overlap
        
        # Check if other agent performs better
        other_success = other.lifetime_success_rate
        my_success = agent.lifetime_success_rate
        
        other_success > my_success + 0.1  # At least 10% better
      end
    end

    def find_successor(agent, reasons)
      superseded_reason = reasons.find { |r| r[:type] == :superseded }
      return entity.agent_plugins.find_by(slug: superseded_reason[:successor]) if superseded_reason
      
      find_better_alternative(agent)
    end

    def preserve_agent_knowledge(agent)
      GlobalKnowledgeArchive.preserve_from_agent(agent)
    end

    def reassign_pending_work(agent, successor)
      return [] unless successor
      
      pending_tasks = agent.scheduled_agent_tasks.where(enabled: true)
      
      reassigned = pending_tasks.map do |task|
        task.update!(agent_plugin: successor)
        task
      end
      
      reassigned
    end

    def create_maturation_notification(agent)
      # Create a notification for the entity users
      UserNotification.create!(
        user: entity.users.first,
        entity: entity,
        title: "Agent Graduated: #{agent.name}",
        message: "#{agent.name} has completed training and is now fully operational.",
        notification_type: 'agent_lifecycle',
        metadata: { agent_id: agent.id, event: 'maturation' }
      )
    rescue => e
      Rails.logger.warn "[Lifecycle] Could not create notification: #{e.message}"
    end
  end
end


