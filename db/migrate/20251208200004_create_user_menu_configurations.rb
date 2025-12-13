class CreateUserMenuConfigurations < ActiveRecord::Migration[7.1]
  def change
    create_table :user_menu_configurations do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :space, null: false  # personal, work, team
      t.jsonb :visible_items, default: []
      t.jsonb :pinned_items, default: []
      t.jsonb :hidden_items, default: []

      t.timestamps
    end

    add_index :user_menu_configurations, [:user_id, :space], unique: true
    add_index :user_menu_configurations, :space
  end
end
