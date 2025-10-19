class AddStoreTypeToRagStores < ActiveRecord::Migration[7.1]
  def change
    # Add store_type column
    add_column :rag_stores, :store_type, :string, default: 'entity', null: false
    add_index :rag_stores, :store_type

    # Add check constraint to ensure entity_id is set correctly based on store_type
    # - system stores must have entity_id = NULL
    # - entity stores must have entity_id NOT NULL
    reversible do |dir|
      dir.up do
        execute <<-SQL
          ALTER TABLE rag_stores
          ADD CONSTRAINT check_entity_required_for_store_type
          CHECK (
            (store_type = 'system' AND entity_id IS NULL) OR
            (store_type = 'entity' AND entity_id IS NOT NULL)
          );
        SQL
      end

      dir.down do
        execute <<-SQL
          ALTER TABLE rag_stores
          DROP CONSTRAINT IF EXISTS check_entity_required_for_store_type;
        SQL
      end
    end

    # Backfill existing records as 'entity' type
    # (already done by default value, but explicit for clarity)
    reversible do |dir|
      dir.up do
        # Ensure all existing records with entity_id are marked as entity type
        execute "UPDATE rag_stores SET store_type = 'entity' WHERE entity_id IS NOT NULL"

        # If any records have no entity_id, mark them as system (shouldn't exist in current schema)
        execute "UPDATE rag_stores SET store_type = 'system' WHERE entity_id IS NULL"
      end
    end
  end
end
