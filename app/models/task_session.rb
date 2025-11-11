class TaskSession < ApplicationRecord
  belongs_to :user
  has_many :task_events, dependent: :destroy
  has_one :workflow_execution, dependent: :destroy
  
  # Parallel processing relationships
  has_many :task_dependencies, dependent: :destroy
  has_many :depends_on_tasks, through: :task_dependencies, source: :depends_on_task
  has_many :dependent_task_relationships, 
           class_name: 'TaskDependency', 
           foreign_key: 'depends_on_task_id',
           dependent: :destroy
  has_many :dependent_tasks, through: :dependent_task_relationships, source: :task_session

  # Status enums
  enum :status, {
    active: "active",
    completed: "completed",
    failed: "failed",
    cancelled: "cancelled"
  }

  # Session type enums
  enum :session_type, {
    autonomous: "autonomous",
    interactive: "interactive",
    hybrid: "hybrid"
  }

  # Store accessors for JSONB fields
  store_accessor :state, :current_step, :wizard_data, :workflow_spec, :artifacts
  store_accessor :metadata, :mode_confidence, :detected_intent, :tool_history

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :parallel_tasks, -> { where.not(parent_conversation_id: nil) }
  scope :by_priority, -> { order(priority: :desc, created_at: :asc) }
  scope :ready_to_execute, -> { where(status: 'active').where('started_at IS NULL') }
  scope :in_progress, -> { where(status: 'active').where.not(started_at: nil) }

  # Event logging
  def add_event(type, payload = {})
    next_sequence = (task_events.maximum(:sequence_number) || 0) + 1
    task_events.create!(
      event_type: type,
      payload: payload,
      sequence_number: next_sequence
    )
  end

  # State reconstruction from events
  def reconstruct_from_events
    reconstructed_state = {}

    task_events.order(:sequence_number).each do |event|
      case event.event_type
      when "step_completed"
        reconstructed_state[:completed_steps] ||= []
        reconstructed_state[:completed_steps] << event.payload["step_id"]
      when "data_collected"
        reconstructed_state[:wizard_data] ||= {}
        reconstructed_state[:wizard_data].merge!(event.payload["data"])
      when "artifact_created"
        reconstructed_state[:artifacts] ||= []
        reconstructed_state[:artifacts] << event.payload["artifact"]
      end
    end

    reconstructed_state
  end

  # Current state helpers
  def current_state
    state.presence || reconstruct_from_events
  end

  def update_state(changes)
    self.state = current_state.merge(changes)
    save!
  end

  # Parallel processing helpers
  def ready_for_execution?
    return false unless status == 'active'
    return false if started_at.present? # Already started
    
    # Check if all blocking dependencies are satisfied
    task_dependencies.blocking.all?(&:satisfied?)
  end
  
  def has_failed_dependencies?
    task_dependencies.any?(&:failed?)
  end
  
  def estimated_duration_ms
    metadata['estimated_duration_ms'] || 5000 # Default 5 seconds
  end
  
  def update_progress(progress, message = nil)
    update!(
      progress: progress,
      state: state.merge(
        last_progress_update: Time.current,
        last_progress_message: message
      )
    )
  end
  
  # Get all results from dependencies
  def dependency_results
    results = {}
    
    depends_on_tasks.completed.each do |task|
      if task.state['result']
        results[task.id] = task.state['result']
      end
    end
    
    results
  end
  
  # Check if this is a voice-related task
  def voice_task?
    task_type&.start_with?('voice_')
  end
  
  # Calculate actual priority for queue ordering
  def effective_priority
    base = priority || 5
    
    # Boost priority for voice tasks
    base += 5 if voice_task?
    
    # Slight boost for tasks with waiting dependents
    base += 1 if dependent_tasks.any?
    
    base
  end
  
  # Workflow helpers
  def mark_step_complete(step_id)
    add_event("step_completed", { step_id: step_id, completed_at: Time.current })
    update_state(current_step: next_step_id(step_id))
  end

  def collect_user_data(data)
    add_event("data_collected", { data: data, collected_at: Time.current })
    wizard_data_hash = (wizard_data || {}).merge(data)
    update_state(wizard_data: wizard_data_hash)
  end

  def add_artifact(type, content, metadata = {})
    artifact = {
      id: SecureRandom.uuid,
      type: type,
      content: content,
      metadata: metadata,
      created_at: Time.current
    }

    add_event("artifact_created", { artifact: artifact })
    artifacts_array = (artifacts || []) + [ artifact ]
    update_state(artifacts: artifacts_array)

    artifact
  end

  private

  def next_step_id(current_step_id)
    return nil unless workflow_spec

    steps = workflow_spec["steps"] || []
    current_index = steps.find_index { |s| s["id"] == current_step_id }

    return nil unless current_index

    next_step = steps[current_index + 1]
    next_step ? next_step["id"] : nil
  end
end
