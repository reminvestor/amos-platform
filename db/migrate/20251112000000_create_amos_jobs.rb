class CreateAmosJobs < ActiveRecord::Migration[7.1]
  def change
    create_table :amos_jobs do |t|
      t.string :job_id, null: false, index: { unique: true }
      t.string :agent_type, null: false
      t.string :session_id, null: false, index: true
      t.string :status, null: false, default: 'queued'
      t.string :status_message
      t.integer :progress, default: 0
      
      t.jsonb :input_data, default: {}
      t.jsonb :result_data, default: {}
      t.jsonb :error_data, default: {}
      
      t.datetime :started_at
      t.datetime :completed_at
      
      t.timestamps
      
      t.index :status
      t.index :agent_type
      t.index [:session_id, :status]
      t.index :created_at
    end
  end
end

