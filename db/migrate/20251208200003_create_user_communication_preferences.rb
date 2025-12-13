class CreateUserCommunicationPreferences < ActiveRecord::Migration[7.1]
  def change
    create_table :user_communication_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :formality_level, default: 3  # 1-5 scale (casual to formal)
      t.integer :verbosity_level, default: 2  # 1-5 scale (brief to detailed)
      t.boolean :humor_enabled, default: false
      t.integer :proactivity_level, default: 3  # 1-5 scale (reactive to proactive)
      t.jsonb :learned_patterns, default: {}
      t.datetime :last_learning_update

      t.timestamps
    end

    add_index :user_communication_preferences, :user_id, unique: true
  end
end
