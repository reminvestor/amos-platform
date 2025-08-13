class CreateScoutMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :scout_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: true, foreign_key: true
      t.string :session_id, null: false
      t.string :role, null: false
      t.text :content, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :scout_messages, [:session_id, :created_at]
  end
end





