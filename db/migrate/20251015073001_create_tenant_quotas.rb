class CreateTenantQuotas < ActiveRecord::Migration[8.0]
  def change
    create_table :tenant_quotas do |t|
      t.references :entity, null: false, foreign_key: true
      t.bigint :row_budget
      t.integer :window_days_cap
      t.integer :qps_limit
      t.jsonb :metadata

      t.timestamps
    end
  end
end
