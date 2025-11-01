# db/migrate/20251031_add_aws_fields_to_entities.rb
class AddAwsFieldsToEntities < ActiveRecord::Migration[7.1]
  def change
    # Bedrock Knowledge Base fields
    add_column :entities, :bedrock_kb_id, :string
    add_column :entities, :bedrock_data_source_id, :string
    add_column :entities, :opensearch_collection_arn, :string
    add_column :entities, :use_bedrock_kb, :boolean, default: false

    # OCR provider preferences
    add_column :entities, :preferred_ocr_provider, :string, default: 'auto'
    add_column :entities, :track_ocr_metrics, :boolean, default: false
    add_column :entities, :notify_on_ocr_failure, :boolean, default: false

    # AWS service configuration
    add_column :entities, :aws_config, :jsonb, default: {}

    # Indexes for faster lookups
    add_index :entities, :bedrock_kb_id
    add_index :entities, :use_bedrock_kb

    # Add Textract-specific fields to rag_documents
    add_column :rag_documents, :textract_status, :string
    add_column :rag_documents, :textract_job_id, :string
    add_column :rag_documents, :textract_result, :jsonb
    add_column :rag_documents, :comprehend_analysis, :jsonb
    add_column :rag_documents, :bedrock_ingestion_status, :string
    add_column :rag_documents, :bedrock_ingested_at, :datetime

    add_index :rag_documents, :textract_job_id
    add_index :rag_documents, :textract_status
    add_index :rag_documents, :bedrock_ingestion_status
  end
end