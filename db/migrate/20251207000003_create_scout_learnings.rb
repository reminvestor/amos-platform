class CreateScoutLearnings < ActiveRecord::Migration[7.1]
  def change
    create_table :scout_learnings do |t|
      t.references :entity, null: false, foreign_key: true
      
      # Learning categorization
      t.string :learning_type, null: false  # task_pattern, tool_usage, delegation, error_recovery, user_pattern
      t.string :context       # What context/situation this learning applies to
      
      # The actual learning
      t.text :learning, null: false  # What Scout learned
      t.text :example         # Example that triggered this learning
      
      # Effectiveness tracking
      t.float :success_rate, default: 0.0  # How often this learning leads to success
      t.integer :apply_count, default: 0   # How many times applied
      t.integer :success_count, default: 0 # How many times successful
      
      # Source and confidence
      t.string :source        # conversation, feedback, observation, correction
      t.float :confidence, default: 0.5
      
      # Active/inactive
      t.boolean :active, default: true
      t.datetime :last_applied_at
      
      t.timestamps
    end
    
    add_index :scout_learnings, [:entity_id, :learning_type]
    add_index :scout_learnings, [:entity_id, :context]
    add_index :scout_learnings, :confidence
    add_index :scout_learnings, :success_rate
  end
end
