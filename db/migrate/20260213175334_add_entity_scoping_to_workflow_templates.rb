class AddEntityScopingToWorkflowTemplates < ActiveRecord::Migration[8.0]
  def change
    add_reference :workflow_templates, :entity, null: true, foreign_key: true
    add_column :workflow_templates, :tags, :jsonb, default: []
    add_column :workflow_templates, :industry, :string
    add_column :workflow_templates, :shared, :boolean, default: false

    add_index :workflow_templates, :industry
    add_index :workflow_templates, :shared
    add_index :workflow_templates, :tags, using: :gin
  end
end
