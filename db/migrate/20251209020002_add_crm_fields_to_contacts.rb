class AddCrmFieldsToContacts < ActiveRecord::Migration[8.0]
  def change
    # Lifecycle stage tracking
    add_column :contacts, :lifecycle_stage, :string, default: 'subscriber'
    # Stages: subscriber -> lead -> mql -> sql -> opportunity -> customer -> evangelist
    
    # Lead scoring
    add_column :contacts, :lead_score, :integer, default: 0
    add_column :contacts, :lead_source, :string
    
    # Assignment - can be assigned to human user or AI agent
    add_column :contacts, :assigned_user_id, :bigint
    add_column :contacts, :assigned_agent_id, :bigint
    
    # Activity tracking
    add_column :contacts, :last_activity_at, :datetime
    add_column :contacts, :last_contacted_at, :datetime
    add_column :contacts, :next_follow_up_at, :datetime
    
    # Conversion tracking
    add_column :contacts, :converted_at, :datetime
    add_column :contacts, :conversion_source, :string
    
    # Indexes
    add_index :contacts, :lifecycle_stage
    add_index :contacts, :lead_score
    add_index :contacts, :assigned_user_id
    add_index :contacts, :assigned_agent_id
    add_index :contacts, :last_activity_at
    add_index :contacts, :next_follow_up_at
    add_index :contacts, [:entity_id, :lifecycle_stage]
    add_index :contacts, [:assigned_user_id, :lifecycle_stage]
    
    # Foreign keys
    add_foreign_key :contacts, :users, column: :assigned_user_id
    add_foreign_key :contacts, :agent_plugins, column: :assigned_agent_id
  end
end
