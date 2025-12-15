class CreateSpaceDefinitions < ActiveRecord::Migration[7.1]
  def change
    create_table :space_definitions do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description
      t.string :icon
      t.text :context_prompt
      t.jsonb :default_tool_loadout, default: []
      t.jsonb :default_menu_items, default: []
      t.integer :display_order, default: 0
      t.boolean :enabled, default: true

      t.timestamps
    end

    add_index :space_definitions, :slug, unique: true
  end
end
