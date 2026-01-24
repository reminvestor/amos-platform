# frozen_string_literal: true

class CreateLoadoutVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :loadout_versions do |t|
      t.references :agent_plugin, null: false, foreign_key: true
      t.integer :version_number, null: false
      t.text :system_prompt_snapshot
      t.jsonb :tools_snapshot, default: []
      t.string :change_reason
      t.references :changed_by, polymorphic: true
      t.jsonb :performance_before, default: {}
      t.jsonb :performance_after, default: {}
      t.boolean :is_active, default: false
      t.datetime :activated_at
      t.timestamps
    end

    add_index :loadout_versions, [:agent_plugin_id, :version_number], unique: true
    add_index :loadout_versions, [:agent_plugin_id, :is_active]
  end
end
