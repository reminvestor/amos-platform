module AiAgents::Pipeline
  class StateMachine
    # State transition rules from spec
    TRANSITIONS = {
      'new' => ['clarifying'],
      'clarifying' => ['planning', 'blocked', 'failed'],
      'planning' => ['implementing', 'clarifying', 'failed'],
      'implementing' => ['review', 'failed'],
      'review' => ['testing', 'implementing', 'failed'],
      'testing' => ['dev', 'implementing', 'failed'],
      'dev' => ['staging', 'failed', 'rolled_back'],
      'staging' => ['awaiting_prod_approval', 'failed', 'rolled_back'],
      'awaiting_prod_approval' => ['prod', 'blocked', 'failed'],
      'prod' => ['done', 'rolled_back'],
      'done' => [],  # Terminal state
      'failed' => ['new'],  # Can retry
      'rolled_back' => ['new'],  # Can retry
      'blocked' => ['clarifying', 'failed']  # Unblock to continue or fail
    }.freeze

    # Check if transition is valid
    def self.can_transition?(from_state, to_state)
      from_state = from_state.to_s
      to_state = to_state.to_s

      return false unless TRANSITIONS.key?(from_state)

      allowed_states = TRANSITIONS[from_state]
      allowed_states.include?(to_state)
    end

    # Get all valid next states for current state
    def self.next_states(current_state)
      TRANSITIONS[current_state.to_s] || []
    end

    # Check if state is terminal
    def self.terminal_state?(state)
      state_str = state.to_s
      ['done', 'failed', 'rolled_back'].include?(state_str)
    end

    # Get state that should trigger a specific agent
    def self.agent_for_state(state)
      case state.to_s
      when 'clarifying'
        'clarifier'
      when 'planning'
        'planner'
      when 'implementing'
        'coder'
      when 'review'
        'reviewer'
      when 'testing', 'dev', 'staging'
        'cua_pack'
      when 'prod'
        'release_manager'
      else
        nil
      end
    end

    # Get next state based on event
    def self.next_state_for_event(current_state, event)
      case event
      when 'ticket.intake'
        'clarifying'
      when 'ticket.clarified'
        'planning'
      when 'plan.ready'
        'implementing'
      when 'pr.opened'
        'review'
      when 'pr.approved'
        'testing'
      when 'pr.needs_changes'
        'implementing'
      when 'tests.passed'
        'dev'
      when 'cua.dev_passed'
        'staging'
      when 'cua.staging_passed'
        'awaiting_prod_approval'
      when 'human.approved'
        'prod'
      when 'prod.promoted'
        'done'
      when 'rollback.triggered'
        'rolled_back'
      when 'execution.failed', 'cua.failed', 'tests.failed'
        'failed'
      when 'interaction.timeout', 'approval.timeout'
        'blocked'
      else
        nil  # Unknown event, no state change
      end
    end

    # Validate state transition with detailed error message
    def self.validate_transition!(from_state, to_state)
      unless can_transition?(from_state, to_state)
        allowed = TRANSITIONS[from_state.to_s] || []
        raise InvalidTransitionError.new(
          "Cannot transition from '#{from_state}' to '#{to_state}'. " \
          "Allowed transitions: #{allowed.join(', ')}"
        )
      end
      true
    end

    # Get human-readable state name
    def self.state_label(state)
      state.to_s.split('_').map(&:capitalize).join(' ')
    end

    # Get state color for UI (Bootstrap classes)
    def self.state_color(state)
      case state.to_s
      when 'new'
        'secondary'
      when 'clarifying', 'planning'
        'info'
      when 'implementing', 'review', 'testing'
        'primary'
      when 'dev', 'staging'
        'warning'
      when 'awaiting_prod_approval'
        'dark'
      when 'prod', 'done'
        'success'
      when 'failed', 'rolled_back'
        'danger'
      when 'blocked'
        'warning'
      else
        'secondary'
      end
    end

    # Get state icon (Font Awesome)
    def self.state_icon(state)
      case state.to_s
      when 'new'
        'fa-file'
      when 'clarifying'
        'fa-question-circle'
      when 'planning'
        'fa-map'
      when 'implementing'
        'fa-code'
      when 'review'
        'fa-search'
      when 'testing'
        'fa-vial'
      when 'dev', 'staging', 'prod'
        'fa-rocket'
      when 'awaiting_prod_approval'
        'fa-pause-circle'
      when 'done'
        'fa-check-circle'
      when 'failed'
        'fa-times-circle'
      when 'rolled_back'
        'fa-undo'
      when 'blocked'
        'fa-ban'
      else
        'fa-circle'
      end
    end

    # Custom exception for invalid transitions
    class InvalidTransitionError < StandardError; end
  end
end
