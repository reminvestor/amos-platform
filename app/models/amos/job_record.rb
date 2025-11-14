module Amos
  # ActiveRecord model for job tracking
  class JobRecord < ApplicationRecord
    self.table_name = 'amos_jobs'
    
    validates :job_id, presence: true, uniqueness: true
    validates :agent_type, presence: true
    validates :status, presence: true
    
    # JSONB columns are automatically serialized by PostgreSQL
    # No need for explicit serialize directives
    
    # Scopes
    scope :active, -> { where(status: ['queued', 'running', 'waiting_for_input']) }
    scope :recent, -> { order(created_at: :desc) }
    scope :completed, -> { where(status: 'completed') }
    scope :failed, -> { where(status: 'failed') }
  end
end

