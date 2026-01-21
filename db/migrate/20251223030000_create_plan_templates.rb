class CreatePlanTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :plan_templates do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :category  # e.g., 'apps', 'integrations', 'workflows', 'modules'
      
      # Triggers for matching user requests
      t.jsonb :trigger_patterns, default: [] # Array of regex patterns
      t.jsonb :keywords, default: []          # Array of keywords to match
      
      # The template phases and steps
      t.jsonb :phases, default: []
      
      # Metadata
      t.string :complexity, default: 'medium' # simple, medium, complex, epic
      t.integer :estimated_duration_minutes
      t.jsonb :common_issues, default: []      # Known issues and how to handle them
      t.jsonb :requirements, default: []       # What's needed before running
      
      # Analytics
      t.integer :times_used, default: 0
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0
      t.float :average_duration_minutes
      t.float :success_rate
      
      # Status
      t.string :status, default: 'active'  # active, deprecated, draft
      t.string :author, default: 'system'  # system, amos, user_generated
      
      t.timestamps
    end

    add_index :plan_templates, :slug, unique: true
    add_index :plan_templates, :category
    add_index :plan_templates, :status
    add_index :plan_templates, :times_used
    add_index :plan_templates, :success_rate
  end
end





