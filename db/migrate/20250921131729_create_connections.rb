class CreateConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :connections do |t|
      t.belongs_to :entity, null: false, foreign_key: true
      t.belongs_to :integration, null: false, foreign_key: true
      t.string :name
      t.integer :status
      t.jsonb :settings
      t.jsonb :allowed_operations
      t.string :rate_limit_tier
      t.integer :daily_write_budget
      t.jsonb :scopes_granted
      t.jsonb :scopes_requested
      t.datetime :last_health_check
      t.jsonb :metadata

      t.timestamps
    end
  end
end
