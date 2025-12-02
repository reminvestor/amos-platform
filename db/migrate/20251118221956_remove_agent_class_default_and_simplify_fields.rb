class RemoveAgentClassDefaultAndSimplifyFields < ActiveRecord::Migration[8.0]
  def change
    # Remove default for agent_class - use StandardPluginExecutor when nil
    change_column_default :agent_plugins, :agent_class, from: "Agents::Specialized::ExecutorAgent", to: nil

    # Make role nullable - RL will learn optimal role over time
    change_column_null :agent_plugins, :role, true
    change_column_default :agent_plugins, :role, from: nil, to: "executor"
  end
end
