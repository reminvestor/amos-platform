class MakePineconeFieldsOptionalInRagStores < ActiveRecord::Migration[8.0]
  def change
    # Make Pinecone fields nullable
    # pgvector is the primary storage for local and AWS deployments
    # Pinecone is optional for extreme scale scenarios (>10M vectors)

    change_column_null :rag_stores, :pinecone_index, true
    change_column_null :rag_stores, :pinecone_namespace, true
  end
end
