class CreateAbTestVariants < ActiveRecord::Migration[8.0]
  def change
    create_table :ab_test_variants do |t|
      t.references :ab_test, null: false, foreign_key: true
      t.string :name, null: false
      t.float :traffic_percentage, default: 50.0, null: false
      t.jsonb :configuration, default: {}
      t.integer :impressions, default: 0
      t.integer :conversions, default: 0
      t.float :conversion_rate, default: 0.0
      t.boolean :is_winner, default: false
      t.boolean :is_control, default: false

      t.timestamps
    end

    add_index :ab_test_variants, [:ab_test_id, :conversion_rate]
    add_index :ab_test_variants, :is_winner
  end
end
