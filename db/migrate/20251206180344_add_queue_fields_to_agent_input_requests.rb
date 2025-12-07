class AddQueueFieldsToAgentInputRequests < ActiveRecord::Migration[8.0]
  def change
    # Priority for ordering questions (higher = more urgent)
    add_column :agent_input_requests, :priority, :integer, default: 0, null: false
    
    # Optional expiration for time-sensitive questions
    add_column :agent_input_requests, :expires_at, :datetime
    
    # If user skipped the question
    add_column :agent_input_requests, :skipped, :boolean, default: false, null: false
    add_column :agent_input_requests, :skipped_reason, :string
    
    # Agent info for display
    add_column :agent_input_requests, :agent_name, :string
    add_column :agent_input_requests, :agent_icon, :string
    
    # Session for routing
    add_column :agent_input_requests, :session_id, :string
    
    add_index :agent_input_requests, [:status, :priority], name: 'idx_input_requests_queue'
    add_index :agent_input_requests, :session_id
    add_index :agent_input_requests, :expires_at
  end
end

