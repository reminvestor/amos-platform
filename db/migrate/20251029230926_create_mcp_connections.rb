class CreateMcpConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_connections do |t|
      t.references :entity, null: false, foreign_key: true, index: true
      t.string :system_type, null: false  # jira, azure_devops, github, azure_repos
      t.string :name, null: false
      t.text :encrypted_config  # Encrypted JSON with credentials and settings
      t.integer :status, null: false, default: 0  # 0=active, 1=inactive, 2=error
      t.jsonb :metadata, default: {}  # org, project, repo filters, etc.
      t.datetime :last_sync_at
      t.datetime :last_health_check_at

      t.timestamps
    end

    add_index :mcp_connections, [:entity_id, :system_type]
    add_index :mcp_connections, :status
    add_index :mcp_connections, :last_sync_at
  end
end
