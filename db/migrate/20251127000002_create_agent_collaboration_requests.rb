class CreateAgentCollaborationRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_collaboration_requests do |t|
      t.references :requesting_agent, null: false, foreign_key: { to_table: :agent_plugins }
      t.references :helper_agent, foreign_key: { to_table: :agent_plugins }
      t.references :entity, null: false, foreign_key: true
      t.references :agent_plugin_execution, foreign_key: true
      t.references :parent_request, foreign_key: { to_table: :agent_collaboration_requests }

      # Request details
      t.string :request_type, null: false  # advice, review, subtask, full_delegation
      t.text :description
      t.jsonb :context, default: {}
      t.string :urgency, default: 'medium'  # low, medium, high, critical
      t.jsonb :required_capabilities, default: []

      # Status tracking
      t.string :status, default: 'pending'  # pending, accepted, in_progress, completed, rejected, expired
      t.datetime :accepted_at
      t.datetime :completed_at
      t.datetime :timeout_at

      # Results
      t.jsonb :response
      t.float :quality_rating
      t.boolean :was_helpful
      t.text :feedback

      # Energy
      t.float :energy_cost
      t.float :energy_reward

      # Delegation depth tracking
      t.integer :depth, default: 0

      t.timestamps
    end

    add_index :agent_collaboration_requests, :status
    add_index :agent_collaboration_requests, :request_type
    add_index :agent_collaboration_requests, [:requesting_agent_id, :status]
    add_index :agent_collaboration_requests, [:helper_agent_id, :status]
    add_index :agent_collaboration_requests, :depth
  end
end

