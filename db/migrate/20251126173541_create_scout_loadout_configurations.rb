class CreateScoutLoadoutConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :scout_loadout_configurations, if_not_exists: true do |t|
      t.references :entity, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :tool_allowlist, default: []  # Array of tool names Scout can use
      t.jsonb :canvas_allowlist, default: ["*"]  # Array of canvas names
      t.jsonb :budgets, default: {}  # max_tokens, max_tool_calls, timeout
      t.boolean :use_tiered_discovery, default: false  # Whether to use RAG for Scout
      t.integer :max_discovered_tools, default: 0  # How many extra tools to discover (0 = none)

      t.timestamps
    end
  end
end
