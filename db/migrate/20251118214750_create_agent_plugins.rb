class CreateAgentPlugins < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_plugins do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :role, null: false
      t.text :description
      t.string :version, default: "1.0.0"
      t.string :status, default: "draft", null: false  # draft, active, deprecated
      t.string :agent_class, default: "Agents::Specialized::ExecutorAgent"
      t.jsonb :configuration, default: {}
      t.jsonb :system_prompt, default: {}
      t.jsonb :capabilities_definition, default: {}
      t.integer :priority, default: 50  # 0-100, higher = preferred
      t.references :entity, null: true, foreign_key: true  # nil = system-wide agent
      t.datetime :last_activated_at

      t.timestamps
    end

    # Indexes for common queries
    add_index :agent_plugins, :slug, unique: true
    add_index :agent_plugins, :status
    add_index :agent_plugins, :role
    add_index :agent_plugins, [:entity_id, :status]
    add_index :agent_plugins, :priority
  end
end
