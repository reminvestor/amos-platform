class CreateMetricDefinitions < ActiveRecord::Migration[8.0]
  def change
    create_table :metric_definitions do |t|
      t.string :name
      t.string :version
      t.text :description
      t.text :expression
      t.string :source
      t.string :time_column
      t.string :grain_default
      t.jsonb :dimensions
      t.jsonb :filters_default
      t.jsonb :quality_rules
      t.string :owner
      t.string :category
      t.boolean :is_active
      t.jsonb :metadata

      t.timestamps
    end
  end
end
