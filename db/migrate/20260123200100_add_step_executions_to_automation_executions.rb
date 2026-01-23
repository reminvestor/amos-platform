# frozen_string_literal: true

class AddStepExecutionsToAutomationExecutions < ActiveRecord::Migration[8.0]
  def change
    # Add step executions tracking to automation_executions
    unless column_exists?(:automation_executions, :step_executions)
      add_column :automation_executions, :step_executions, :jsonb, default: []
    end
    unless column_exists?(:automation_executions, :duration_ms)
      add_column :automation_executions, :duration_ms, :integer
    end
  end
end
