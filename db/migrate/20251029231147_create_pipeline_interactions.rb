class CreatePipelineInteractions < ActiveRecord::Migration[8.0]
  def change
    create_table :pipeline_interactions do |t|
      # Parent pipeline execution
      t.references :pipeline_execution, null: false, foreign_key: true, index: true

      # User who responded (nullable until answered)
      t.references :user, null: true, foreign_key: true

      # Interaction classification
      t.string :interaction_type, null: false  # clarification, approval, rejection

      # Communication channel
      t.string :channel, null: false  # slack, teams, email

      # External system reference (Slack thread ID, Teams message ID, etc.)
      t.string :external_thread_id

      # Question and response content
      t.text :question, null: false
      t.text :response

      # Status tracking
      t.integer :status, null: false, default: 0  # 0=pending, 1=answered, 2=timeout

      # Timing
      t.datetime :asked_at, null: false
      t.datetime :answered_at
      t.datetime :timeout_at

      t.timestamps
    end

    # Indexes for common queries
    add_index :pipeline_interactions, :interaction_type
    add_index :pipeline_interactions, :status
    add_index :pipeline_interactions, [:pipeline_execution_id, :status]
    add_index :pipeline_interactions, :channel
    add_index :pipeline_interactions, :external_thread_id
  end
end
