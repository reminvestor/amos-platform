# frozen_string_literal: true

class UpdateRagStoreConstraintForAgents < ActiveRecord::Migration[8.0]
  def up
    # Drop the old constraint
    execute <<-SQL
      ALTER TABLE rag_stores
      DROP CONSTRAINT IF EXISTS check_entity_required_for_store_type;
    SQL

    # Add updated constraint that also allows 'agent' store type
    # - system: entity_id must be NULL
    # - entity: entity_id must be present  
    # - agent: entity_id can be NULL (for system-wide agents) or present (for entity agents)
    execute <<-SQL
      ALTER TABLE rag_stores
      ADD CONSTRAINT check_entity_required_for_store_type
      CHECK (
        (store_type = 'system' AND entity_id IS NULL) OR
        (store_type = 'entity' AND entity_id IS NOT NULL) OR
        (store_type = 'agent')
      );
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE rag_stores
      DROP CONSTRAINT IF EXISTS check_entity_required_for_store_type;
    SQL

    execute <<-SQL
      ALTER TABLE rag_stores
      ADD CONSTRAINT check_entity_required_for_store_type
      CHECK (
        (store_type = 'system' AND entity_id IS NULL) OR
        (store_type = 'entity' AND entity_id IS NOT NULL)
      );
    SQL
  end
end
