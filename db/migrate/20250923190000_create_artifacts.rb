class CreateArtifacts < ActiveRecord::Migration[7.1]
  def change
    create_table :artifacts do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.string :name, null: false
      t.string :source, null: false, default: 'integration'

      t.bigint :connection_id
      t.string :operation_id

      t.jsonb :schema, null: false, default: {}
      t.jsonb :sample, null: false, default: []
      t.integer :row_count

      t.string :storage_ref
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :artifacts, :connection_id
    add_index :artifacts, :operation_id
    add_index :artifacts, :storage_ref
  end
end
