class CreateOpportunities < ActiveRecord::Migration[8.0]
  def change
    create_table :opportunities do |t|
      t.references :contact, null: false, foreign_key: true
      t.references :user, foreign_key: true                    # Owner (human) - nullable for AI-only
      t.references :entity, null: false, foreign_key: true
      t.references :assigned_agent, foreign_key: { to_table: :agent_plugins }
      
      t.string :name, null: false
      t.string :stage, null: false, default: 'lead'
      t.decimal :value, precision: 12, scale: 2
      t.integer :probability, default: 10                      # 0-100%
      t.date :expected_close_date
      t.date :actual_close_date
      t.string :lost_reason
      t.string :source                                         # landing_page, referral, direct, etc.
      t.text :notes
      t.jsonb :metadata, default: {}
      t.integer :position                                      # For kanban ordering within stage
      
      t.timestamps
    end

    add_index :opportunities, :stage
    add_index :opportunities, :source
    add_index :opportunities, [:entity_id, :stage]
    add_index :opportunities, [:user_id, :stage]
    add_index :opportunities, [:assigned_agent_id, :stage]
    add_index :opportunities, :expected_close_date
  end
end
