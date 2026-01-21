class AddPlanDependencies < ActiveRecord::Migration[7.1]
  def change
    # Add dependency tracking to execution_plans
    add_column :execution_plans, :depends_on_plan_ids, :jsonb, default: [], null: false
    add_column :execution_plans, :blocks_plan_ids, :jsonb, default: [], null: false
    add_column :execution_plans, :priority, :integer, default: 50, null: false

    add_index :execution_plans, :priority
  end
end





