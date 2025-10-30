module AiAgents::Pipeline
  class Orchestrator
    attr_reader :pipeline_execution

    def initialize(pipeline_execution)
      @pipeline_execution = pipeline_execution
    end

    # Main orchestration method - processes current state and determines next action
    def process!
      Rails.logger.info "🔄 Processing pipeline execution #{pipeline_execution.id} in state: #{pipeline_execution.status}"

      # Start execution if not started
      pipeline_execution.start! unless pipeline_execution.started_at

      # Check if execution is complete
      if pipeline_execution.terminal_state?
        Rails.logger.info "✅ Pipeline #{pipeline_execution.id} is in terminal state: #{pipeline_execution.status}"
        return { success: true, terminal: true, state: pipeline_execution.status }
      end

      # Check if blocked by pending interactions
      if pipeline_execution.blocked_by_interaction?
        Rails.logger.info "⏸️  Pipeline #{pipeline_execution.id} is blocked by pending interactions"
        return { success: true, blocked: true, message: 'Awaiting human interaction' }
      end

      # Process current state
      result = process_current_state

      # If successful and not terminal, schedule next step
      if result[:success] && !result[:terminal]
        schedule_next_step
      end

      result
    rescue => e
      Rails.logger.error "❌ Pipeline orchestration failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      pipeline_execution.fail!(e.message)
      { success: false, error: e.message }
    end

    private

    def process_current_state
      case pipeline_execution.status
      when 'new'
        # Create ticket.intake event and transition to clarifying
        create_event('ticket.intake', source: 'system')
        transition_to_next_state('clarifying')

      when 'clarifying'
        execute_agent('clarifier')

      when 'planning'
        execute_agent('planner')

      when 'implementing'
        execute_agent('coder')

      when 'review'
        execute_agent('reviewer')

      when 'testing', 'dev', 'staging'
        execute_agent('cua_pack')

      when 'awaiting_prod_approval'
        request_production_approval

      when 'prod'
        execute_agent('release_manager')

      when 'blocked'
        handle_blocked_state

      else
        { success: true, message: "State #{pipeline_execution.status} requires manual intervention" }
      end
    end

    def execute_agent(agent_id)
      Rails.logger.info "🤖 Executing agent: #{agent_id} for pipeline #{pipeline_execution.id}"

      # Check if agent already executed for current state
      existing_execution = pipeline_execution.agent_executions
                                             .where(agent_id: agent_id)
                                             .where('created_at > ?', pipeline_execution.state_changed_at || 1.hour.ago)
                                             .last

      if existing_execution&.status_completed?
        Rails.logger.info "✅ Agent #{agent_id} already completed for current state"
        return handle_agent_completion(agent_id, existing_execution)
      end

      # Create or resume agent execution
      agent_execution = existing_execution || pipeline_execution.agent_executions.create!(
        agent_id: agent_id,
        inputs: build_agent_inputs(agent_id)
      )

      # Queue agent execution job
      AgentExecutionJob.perform_later(agent_execution.id)

      { success: true, agent: agent_id, agent_execution_id: agent_execution.id, status: 'queued' }
    end

    def build_agent_inputs(agent_id)
      base_inputs = {
        ticket_id: pipeline_execution.ticket_id,
        ticket_title: pipeline_execution.ticket_title,
        ticket_description: pipeline_execution.ticket_description,
        ticket_url: pipeline_execution.ticket_url,
        entity_id: pipeline_execution.entity_id
      }

      case agent_id
      when 'clarifier'
        base_inputs.merge(
          ticket_metadata: pipeline_execution.ticket_metadata
        )

      when 'planner'
        # Get clarifications from clarifier
        clarification_artifact = pipeline_execution.artifacts_of_type('clarifications').last
        base_inputs.merge(
          clarifications: clarification_artifact&.get_content || {},
          ticket_metadata: pipeline_execution.ticket_metadata
        )

      when 'coder'
        # Get plan from planner
        plan_artifact = pipeline_execution.artifacts_of_type('plan').last
        test_spec_artifact = pipeline_execution.artifacts_of_type('test_spec').last

        base_inputs.merge(
          plan: plan_artifact&.get_content,
          test_spec: test_spec_artifact&.get_content,
          repository: pipeline_execution.repository,
          branch_name: pipeline_execution.branch_name
        )

      when 'reviewer'
        base_inputs.merge(
          pr_url: pipeline_execution.pr_url,
          pr_id: pipeline_execution.pr_id,
          repository: pipeline_execution.repository
        )

      when 'cua_pack'
        base_inputs.merge(
          environment: pipeline_execution.status,  # dev, staging
          pr_url: pipeline_execution.pr_url,
          repository: pipeline_execution.repository
        )

      else
        base_inputs
      end
    end

    def handle_agent_completion(agent_id, agent_execution)
      # Determine next state based on agent outputs
      outputs = agent_execution.outputs || {}

      case agent_id
      when 'clarifier'
        if outputs['needs_clarification']
          # Block and create interaction
          create_clarification_interaction(outputs['questions'])
          { success: true, state: 'blocked', message: 'Awaiting clarification' }
        else
          create_event('ticket.clarified', source: 'agent', payload: outputs)
          transition_to_next_state('planning')
        end

      when 'planner'
        create_event('plan.ready', source: 'agent', payload: outputs)
        transition_to_next_state('implementing')

      when 'coder'
        # PR should be opened
        create_event('pr.opened', source: 'agent', payload: {
          pr_url: outputs['pr_url'],
          pr_id: outputs['pr_id'],
          branch: outputs['branch_name']
        })
        transition_to_next_state('review')

      when 'reviewer'
        if outputs['approved']
          create_event('pr.approved', source: 'agent', payload: outputs)
          transition_to_next_state('testing')
        else
          create_event('pr.needs_changes', source: 'agent', payload: outputs)
          transition_to_next_state('implementing')
        end

      when 'cua_pack'
        current_state = pipeline_execution.status
        if outputs['passed']
          case current_state
          when 'testing'
            create_event('tests.passed', source: 'agent', payload: outputs)
            transition_to_next_state('dev')
          when 'dev'
            create_event('cua.dev_passed', source: 'agent', payload: outputs)
            transition_to_next_state('staging')
          when 'staging'
            create_event('cua.staging_passed', source: 'agent', payload: outputs)
            transition_to_next_state('awaiting_prod_approval')
          end
        else
          create_event('cua.failed', source: 'agent', payload: outputs)
          transition_to_next_state('failed')
        end

      else
        { success: true, message: "Agent #{agent_id} completed" }
      end
    end

    def create_clarification_interaction(questions)
      return if questions.blank?

      pipeline_execution.pipeline_interactions.create!(
        interaction_type: 'clarification',
        channel: ENV['DEFAULT_NOTIFICATION_CHANNEL'] || 'slack',
        question: questions.is_a?(Array) ? questions.join("\n\n") : questions.to_s,
        asked_at: Time.current,
        timeout_at: 2.hours.from_now
      )

      pipeline_execution.update!(status: :blocked)
    end

    def request_production_approval
      Rails.logger.info "📋 Requesting production approval for pipeline #{pipeline_execution.id}"

      # Create approval interaction
      pipeline_execution.pipeline_interactions.create!(
        interaction_type: 'approval',
        channel: ENV['APPROVAL_CHANNEL'] || 'slack',
        question: "Approve deployment to production for #{pipeline_execution.ticket_title}?\n\nPR: #{pipeline_execution.pr_url}",
        asked_at: Time.current,
        timeout_at: 4.hours.from_now
      )

      { success: true, message: 'Awaiting production approval' }
    end

    def handle_blocked_state
      Rails.logger.info "⏸️  Pipeline #{pipeline_execution.id} is blocked"

      # Check if interactions have been resolved
      if pipeline_execution.pending_interactions.none?
        # All interactions resolved, determine appropriate next state
        Rails.logger.info "✅ All interactions resolved, continuing pipeline"

        # Derive next state from the last answered interaction
        last_interaction = pipeline_execution.pipeline_interactions
                                            .where(status: 'answered')
                                            .order(answered_at: :desc)
                                            .first

        next_state = if last_interaction
                      case last_interaction.interaction_type
                      when 'clarification'
                        # After clarification, proceed to planning
                        'planning'
                      when 'approval'
                        # After approval, proceed to production
                        'prod'
                      when 'rejection'
                        # After rejection, go back to implementing
                        'implementing'
                      else
                        # Default fallback
                        'clarifying'
                      end
                    else
                      # No interaction found, check last event
                      last_event = pipeline_execution.pipeline_events.order(created_at: :desc).first
                      if last_event
                        AiAgents::Pipeline::StateMachine.next_state_for_event(pipeline_execution.status, last_event.event_type) || 'clarifying'
                      else
                        'clarifying'
                      end
                    end

        transition_to_next_state(next_state)
      else
        { success: true, message: 'Still blocked by pending interactions' }
      end
    end

    def create_event(event_type, source:, payload: {})
      pipeline_execution.pipeline_events.create!(
        event_type: event_type,
        source: source,
        payload: payload
      )
    end

    def transition_to_next_state(new_state)
      event_type = "state.transition.#{pipeline_execution.status}_to_#{new_state}"

      pipeline_execution.transition_to!(
        new_state,
        event: event_type,
        metadata: { previous_state: pipeline_execution.status }
      )

      { success: true, state: new_state }
    end

    def schedule_next_step
      # Schedule next orchestration in 5 seconds
      ProcessPipelineJob.set(wait: 5.seconds).perform_later(pipeline_execution.id)
    end
  end
end
