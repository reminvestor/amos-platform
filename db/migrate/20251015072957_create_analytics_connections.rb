class CreateAnalyticsConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :analytics_connections do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name
      t.integer :connection_type
      t.integer :status
      t.text :credentials
      t.jsonb :config
      t.datetime :last_health_check
      t.jsonb :metadata

      t.timestamps
    end
  end
end
