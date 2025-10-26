class AddTtsPreferencesToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :tts_preferences, :jsonb, default: {}, null: false
    add_index :users, :tts_preferences, using: :gin
  end
end
