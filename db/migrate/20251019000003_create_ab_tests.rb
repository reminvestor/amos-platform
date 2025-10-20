class CreateAbTests < ActiveRecord::Migration[8.0]
  def change
    create_table :ab_tests do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :testable, polymorphic: true, null: false
      t.string :name, null: false
      t.string :status, default: 'draft', null: false
      t.text :hypothesis
      t.string :metric, default: 'conversion_rate' # conversion_rate, open_rate, click_rate
      t.float :confidence_level, default: 0.95 # 95% confidence
      t.integer :minimum_sample_size, default: 100
      t.datetime :started_at
      t.datetime :ended_at
      t.jsonb :results
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ab_tests, [:entity_id, :status]
    add_index :ab_tests, [:testable_type, :testable_id]
    add_index :ab_tests, :started_at
  end
end
