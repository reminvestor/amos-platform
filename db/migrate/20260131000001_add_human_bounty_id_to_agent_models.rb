class AddHumanBountyIdToAgentModels < ActiveRecord::Migration[7.1]
  def change
    # Only add columns if the tables exist
    if table_exists?(:agent_goals)
      add_reference :agent_goals, :human_bounty, foreign_key: { to_table: :bounties }, null: true
    end

    if table_exists?(:platform_anomalies)
      add_reference :platform_anomalies, :human_bounty, foreign_key: { to_table: :bounties }, null: true
    end
  end
end
