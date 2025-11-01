class AddBedrockKnowledgeBaseFieldsToEntities < ActiveRecord::Migration[8.0]
  def change
    add_column :entities, :bedrock_knowledge_base_id, :string
    add_column :entities, :bedrock_kb_status, :string
    add_column :entities, :bedrock_last_ingestion_job_id, :string

    # Add indexes for faster lookups
    add_index :entities, :bedrock_knowledge_base_id
    add_index :entities, :bedrock_kb_status
    add_index :entities, :bedrock_last_ingestion_job_id
  end
end
