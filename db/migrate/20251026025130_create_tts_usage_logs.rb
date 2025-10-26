class CreateTtsUsageLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :tts_usage_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.integer :character_count
      t.string :voice_id
      t.float :cost_cents

      t.timestamps
    end
  end
end
