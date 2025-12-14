# frozen_string_literal: true

class AddHubFieldsToTeamChannels < ActiveRecord::Migration[8.0]
  def change
    # Extend team_channels for Hub functionality
    add_column :team_channels, :purpose, :text
    add_column :team_channels, :topic, :string
    add_column :team_channels, :is_private, :boolean, default: false
    add_column :team_channels, :member_count, :integer, default: 0
    add_column :team_channels, :last_activity_at, :datetime
    
    # Agent roster - which agents are active in this channel
    add_column :team_channels, :agent_roster, :jsonb, default: []
    add_column :team_channels, :auto_invite_agents, :boolean, default: true
    
    # Channel-level settings
    add_column :team_channels, :allow_agent_initiation, :boolean, default: true  # Agents can start threads
    add_column :team_channels, :require_human_approval, :boolean, default: false  # Agent actions need approval
    
    add_index :team_channels, :is_private
    add_index :team_channels, :last_activity_at
    add_index :team_channels, :agent_roster, using: :gin
  end
end
