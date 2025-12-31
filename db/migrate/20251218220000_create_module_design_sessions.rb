class CreateModuleDesignSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :module_design_sessions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :app_module, foreign_key: true
      t.string :status, default: 'gathering_requirements'
      t.string :module_name
      t.text :user_description
      t.jsonb :proposed_schema, default: {}
      t.jsonb :user_feedback, default: []
      t.jsonb :final_schema, default: {}
      t.jsonb :conversation_context, default: {}
      t.integer :iteration_count, default: 0
      t.datetime :completed_at
      t.timestamps
    end
    
    add_index :module_design_sessions, :status
    add_index :module_design_sessions, [:entity_id, :status]
  end
end
