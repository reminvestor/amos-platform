class CreateCommunityEnergyPool < ActiveRecord::Migration[8.0]
  def change
    create_table :community_energy_pools do |t|
      t.references :entity, null: false, foreign_key: true

      t.float :current_balance, default: 0.0, null: false
      t.float :total_deposited, default: 0.0, null: false
      t.float :total_distributed, default: 0.0, null: false
      t.integer :distribution_count, default: 0

      t.datetime :last_distribution_at

      t.timestamps
    end

    # Index already created by t.references
  end
end

