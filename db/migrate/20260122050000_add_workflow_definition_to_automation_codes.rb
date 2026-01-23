class AddWorkflowDefinitionToAutomationCodes < ActiveRecord::Migration[8.0]
  def change
    add_column :automation_codes, :workflow_definition, :jsonb, default: {}
  end
end
