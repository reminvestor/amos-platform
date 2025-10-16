class CreateDataContracts < ActiveRecord::Migration[8.0]
  def change
    create_table :data_contracts do |t|
      t.string :name
      t.string :version
      t.string :entity_type
      t.jsonb :schema_definition
      t.jsonb :privacy_rules
      t.string :freshness_slo
      t.boolean :is_active
      t.jsonb :metadata

      t.timestamps
    end
  end
end
