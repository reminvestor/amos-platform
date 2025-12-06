class CreateFactoryTestRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :factory_test_runs do |t|
      t.references :factory_test_criteria, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      
      # Test execution tracking
      t.integer :attempt_number, null: false, default: 1
      t.string :status, null: false, default: 'pending'  # pending, running, passed, failed, skipped, error
      
      # Results
      t.boolean :passed, default: false
      t.text :actual_output
      t.jsonb :actual_values, default: {}
      t.text :error_message
      t.text :diff_summary  # What was different from expected
      
      # For semantic tests
      t.float :similarity_score  # 0.0 to 1.0
      t.text :ai_evaluation  # AI's explanation of pass/fail
      
      # For HTTP tests
      t.integer :actual_status_code
      t.jsonb :actual_headers, default: {}
      t.float :response_time_ms
      
      # Performance tracking
      t.integer :duration_ms
      t.integer :tokens_used
      
      # AI feedback for retry
      t.text :ai_feedback  # What the AI should fix
      t.text :fix_suggestion  # Specific fix suggestion
      
      # Metadata
      t.jsonb :metadata, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      
      t.timestamps
    end

    add_index :factory_test_runs, [:factory_test_criteria_id, :attempt_number], name: 'idx_test_runs_attempt'
    add_index :factory_test_runs, :status
    add_index :factory_test_runs, :passed
    add_index :factory_test_runs, [:created_at, :status], name: 'idx_test_runs_recent'
    
    # Create a test session to group test runs
    create_table :factory_test_sessions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      
      # What is being tested
      t.string :testable_type, null: false
      t.bigint :testable_id, null: false
      
      # Session tracking
      t.integer :attempt_number, null: false, default: 1
      t.integer :max_attempts, default: 3
      t.string :status, null: false, default: 'pending'  # pending, running, passed, failed, delivered
      
      # Results summary
      t.integer :total_tests, default: 0
      t.integer :passed_tests, default: 0
      t.integer :failed_tests, default: 0
      t.integer :skipped_tests, default: 0
      t.float :overall_score  # 0.0 to 1.0
      
      # Timing
      t.integer :total_duration_ms
      t.datetime :started_at
      t.datetime :completed_at
      
      # Final delivery
      t.boolean :delivered, default: false
      t.datetime :delivered_at
      t.text :delivery_notes
      
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :factory_test_sessions, [:testable_type, :testable_id], name: 'idx_test_sessions_testable'
    add_index :factory_test_sessions, :status
    add_index :factory_test_sessions, [:testable_type, :testable_id, :attempt_number], 
              unique: true, name: 'idx_test_sessions_unique_attempt'
    
    # Link test runs to sessions
    add_reference :factory_test_runs, :factory_test_session, foreign_key: true
  end
end

