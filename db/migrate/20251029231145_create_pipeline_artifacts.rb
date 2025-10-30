class CreatePipelineArtifacts < ActiveRecord::Migration[8.0]
  def change
    create_table :pipeline_artifacts do |t|
      # Parent pipeline execution
      t.references :pipeline_execution, null: false, foreign_key: true, index: true

      # Which agent created this artifact (optional - may be null for manual uploads)
      t.references :agent_execution, null: true, foreign_key: true, index: true

      # Artifact classification
      t.string :artifact_type, null: false  # plan, test_spec, review_report, code, screenshot, etc.
      t.string :file_name, null: false

      # Storage - either inline content (small files) or S3 path (large files)
      t.text :content  # For files < 100KB
      t.string :storage_path  # S3 path for large files
      t.integer :file_size, default: 0

      # Additional metadata
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Indexes for common queries
    add_index :pipeline_artifacts, :artifact_type
    add_index :pipeline_artifacts, [:pipeline_execution_id, :artifact_type]
  end
end
