class CreateAgentSchoolEnrollments < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_school_enrollments do |t|
      t.references :agent_plugin, null: false, foreign_key: true
      t.references :student_agent, foreign_key: { to_table: :agent_plugins }
      t.references :entity, null: false, foreign_key: true

      # Enrollment details
      t.string :status, default: 'enrolled', null: false  # enrolled, diagnosing, curriculum, testing, graduated, retry, probation, expelled
      t.string :enrollment_reason, null: false  # zero_energy, poor_performance, manual
      t.integer :attempt_number, default: 1, null: false

      # Diagnosis results
      t.jsonb :diagnosis, default: {}
      t.jsonb :curriculum_applied, default: []
      t.jsonb :comparison_results, default: {}
      t.jsonb :irreplaceability_assessment, default: {}

      # Outcome
      t.string :outcome  # success, failure, irreplaceable_failure, inconclusive

      # Timestamps
      t.datetime :enrolled_at
      t.datetime :diagnosis_completed_at
      t.datetime :curriculum_completed_at
      t.datetime :testing_started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :agent_school_enrollments, :status
    add_index :agent_school_enrollments, [:agent_plugin_id, :attempt_number]
    add_index :agent_school_enrollments, :outcome
  end
end

