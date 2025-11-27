class CreateAgentRelationships < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_relationships do |t|
      t.references :requester, null: false, foreign_key: { to_table: :agent_plugins }
      t.references :helper, null: false, foreign_key: { to_table: :agent_plugins }
      t.references :entity, null: false, foreign_key: true

      # Collaboration statistics
      t.integer :total_collaborations, default: 0, null: false
      t.integer :successful_collaborations, default: 0, null: false
      t.float :total_quality, default: 0.0
      t.bigint :total_response_time_ms, default: 0
      t.jsonb :helpfulness_ratings, default: []

      # Computed scores
      t.float :compatibility_score, default: 0.5
      t.float :trust_score, default: 0.5

      # Inheritance tracking
      t.references :inherited_from, foreign_key: { to_table: :agent_relationships }

      t.timestamps
    end

    add_index :agent_relationships, [:requester_id, :helper_id], unique: true
    add_index :agent_relationships, :compatibility_score
  end
end

