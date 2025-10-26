class CreateObservabilityEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :observability_events do |t|
      t.string :event_type, null: false
      t.references :entity, foreign_key: true
      t.references :user, foreign_key: true
      t.string :resource_type
      t.bigint :resource_id
      t.jsonb :metadata, default: {}
      t.integer :duration_ms
      t.string :status
      t.text :error_message
      
      t.timestamps
    end
    
    add_index :observability_events, :event_type
    add_index :observability_events, :status
    add_index :observability_events, [:entity_id, :created_at]
    add_index :observability_events, [:resource_type, :resource_id]
    add_index :observability_events, :created_at
  end
end
