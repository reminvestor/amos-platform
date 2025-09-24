class CreateWorkflowTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_templates do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :category, null: false # analytics, campaign_creation, data_import, etc.
      t.text :description
      t.jsonb :template_spec, null: false, default: {} # The DAG template with placeholders
      t.jsonb :metadata, null: false, default: {}
      t.boolean :is_active, default: true
      t.boolean :is_system, default: false # System templates can't be edited by users
      
      t.timestamps
    end
    
    add_index :workflow_templates, :slug, unique: true
    add_index :workflow_templates, :category
    add_index :workflow_templates, :is_active
  end
end
