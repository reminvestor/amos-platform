class CreateCustomAgentDefinitions < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_agent_definitions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :agent_type, null: false
      t.jsonb :definition, null: false, default: {}
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :custom_agent_definitions, [:entity_id, :name], unique: true
    add_index :custom_agent_definitions, :agent_type
  end
end
