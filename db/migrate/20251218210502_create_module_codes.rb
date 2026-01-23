# frozen_string_literal: true

class CreateModuleCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :module_codes do |t|
      t.references :app_module, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      # Code identification
      t.string :name, null: false  # Product, InventoryLevel, etc.
      t.string :code_type, null: false  # model, migration, tool, agent, scheduled_task
      
      # The actual generated code
      t.text :content, null: false
      
      # For models - the schema definition
      t.jsonb :schema_definition, default: {}
      # {
      #   table_name: 'products',
      #   fields: [
      #     { name: 'name', type: 'string', null: false },
      #     { name: 'sku', type: 'string', null: false, unique: true },
      #     { name: 'quantity', type: 'integer', default: 0 },
      #     { name: 'reorder_threshold', type: 'integer', default: 10 }
      #   ],
      #   associations: [
      #     { type: 'belongs_to', model: 'Category' }
      #   ],
      #   indexes: [
      #     { fields: ['sku'], unique: true }
      #   ]
      # }
      
      # Versioning
      t.integer :version, default: 1
      t.text :previous_content
      
      # Status
      t.string :status, default: 'generated'  # generated, validated, deployed, failed
      t.text :validation_errors
      t.datetime :deployed_at
      
      # Execution context
      t.boolean :loaded, default: false  # Is this code currently loaded?
      t.datetime :last_loaded_at
      
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :module_codes, [:app_module_id, :name, :code_type], unique: true
    add_index :module_codes, :code_type
    add_index :module_codes, :status
    add_index :module_codes, :loaded
  end
end





