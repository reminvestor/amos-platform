class CreateScoutConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :scout_conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :session_id
      t.string :message_type
      t.text :content
      t.jsonb :metadata

      t.timestamps
    end
  end
end
