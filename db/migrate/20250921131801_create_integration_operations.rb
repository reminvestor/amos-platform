class CreateIntegrationOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :integration_operations do |t|
      t.belongs_to :integration, null: false, foreign_key: true
      t.string :operation_id
      t.string :name
      t.text :description
      t.string :http_method
      t.string :path_template
      t.jsonb :request_schema
      t.jsonb :response_schema
      t.integer :pagination_strategy
      t.boolean :is_idempotent
      t.boolean :requires_confirmation
      t.integer :max_limit
      t.text :documentation
      t.jsonb :examples
      t.string :version
      t.datetime :deprecated_at

      t.timestamps
    end
    add_index :integration_operations, :operation_id
  end
end
