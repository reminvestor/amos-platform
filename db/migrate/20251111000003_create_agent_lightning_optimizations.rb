class CreateAgentLightningOptimizations < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_lightning_optimizations do |t|
      # Basic association and identification
      t.references :entity, null: false, foreign_key: true
      t.references :agent_training_job, null: true, foreign_key: true
      t.string :optimization_id, null: false, unique: true, index: true

      # Optimization context and results
      t.string :status, default: "pending", null: false # pending, applied, rolled_back, failed
      t.jsonb :before_prompts, default: {}, null: false # Original prompts before optimization
      t.jsonb :after_prompts, default: {}, null: false # Optimized prompts from training
      t.decimal :improvement_percentage, precision: 5, scale: 2, default: 0.0

      # Template tracking
      t.integer :templates_updated, default: 0
      t.jsonb :templates_modified, default: [], null: false # Array of template names updated
      t.jsonb :context_types_optimized, default: [], null: false # gather_context, execute_goal, validate_result

      # Prompts optimized breakdown
      t.integer :prompts_optimized, default: 0

      # Timestamps for lifecycle tracking
      t.datetime :applied_at, null: true # When optimization was applied
      t.datetime :rolled_back_at, null: true # When optimization was rolled back
      t.integer :rollback_count, default: 0 # Number of times this optimization was rolled back

      # Metadata for debugging and analysis
      t.jsonb :metadata, default: {}, null: false # Additional context about the optimization
      t.text :error_message, null: true # Error message if optimization failed

      t.timestamps
    end

    add_index :agent_lightning_optimizations, :status
    add_index :agent_lightning_optimizations, [:entity_id, :created_at]
    add_index :agent_lightning_optimizations, [:status, :created_at]
  end
end
