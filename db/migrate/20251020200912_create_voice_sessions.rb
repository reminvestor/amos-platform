class CreateVoiceSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :voice_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :session_id, null: false
      t.string :status, null: false, default: "active"
      t.jsonb :context, default: {}
      t.jsonb :transcript_history, default: []
      t.jsonb :metadata, default: {}
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end

    add_index :voice_sessions, :session_id, unique: true
    add_index :voice_sessions, :status
    add_index :voice_sessions, [ :entity_id, :status ]
    add_index :voice_sessions, :started_at
  end
end
