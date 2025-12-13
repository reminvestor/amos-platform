class CreateUserSpacePreferences < ActiveRecord::Migration[7.1]
  def change
    create_table :user_space_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.string :active_space, default: 'work'
      t.jsonb :personal_settings, default: {}
      t.jsonb :work_settings, default: {}
      t.jsonb :team_settings, default: {}
      t.boolean :onboarding_completed, default: false
      t.jsonb :enabled_spaces, default: ['personal', 'work', 'team']

      t.timestamps
    end

    add_index :user_space_preferences, :user_id, unique: true
    add_index :user_space_preferences, :active_space
  end
end
