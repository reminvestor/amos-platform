class TaskDependency < ApplicationRecord
  belongs_to :task_session
  belongs_to :depends_on_task, class_name: 'TaskSession', foreign_key: 'depends_on_task_id'
  
  # Relationship types (legacy - kept for compatibility)
  RELATIONSHIP_TYPES = {
    blocks: 'blocks',      # Must complete before dependent can start
    informs: 'informs',    # Provides context but doesn't block
    optional: 'optional'   # Nice to have but not required
  }.freeze
  
  # Dependency types (new column)
  enum :dependency_type, {
    blocking: "blocking",        # Must complete before dependent can start
    informational: "informational", # Provides context but doesn't block  
    optional: "optional"         # Nice to have but not required
  }
  
  # Status (new column)
  enum :status, {
    pending: "pending",
    satisfied: "satisfied",
    failed: "failed"
  }
  
  validates :relationship_type, inclusion: { in: RELATIONSHIP_TYPES.values }, allow_nil: true
  
  # Scopes
  scope :blocking, -> { where(dependency_type: 'blocking') }
  scope :informational, -> { where(dependency_type: 'informational') }
  
  # Check if dependency is satisfied
  def satisfied?
    case dependency_type || relationship_type  # Fallback to relationship_type for legacy data
    when 'blocking', 'blocks'
      depends_on_task.status == 'completed'
    when 'informational', 'informs', 'optional'
      # These don't block execution
      true
    else
      false
    end
  end
  
  # Check if dependency has failed
  def failed?
    depends_on_task.status.in?(['failed', 'cancelled'])
  end
end
