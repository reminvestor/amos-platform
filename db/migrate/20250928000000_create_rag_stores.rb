class CreateRagStores < ActiveRecord::Migration[7.1]
  def change
    create_table :rag_stores do |t|
      t.string :name, null: false
      t.string :app_name, null: false
      t.string :pinecone_index, null: false
      t.string :pinecone_namespace, null: false
      t.integer :chunk_count, default: 0
      t.jsonb :metadata, default: {}
      t.string :status, default: 'active'
      t.references :user, foreign_key: true
      t.references :entity, foreign_key: true

      t.timestamps
    end

    add_index :rag_stores, :app_name
    add_index :rag_stores, :status
    add_index :rag_stores, [ :pinecone_index, :pinecone_namespace ], unique: true
  end
end
