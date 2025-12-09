class FixScoutMessagesDuplicateDetectionIndex < ActiveRecord::Migration[8.0]
  def up
    # Remove the problematic index that includes the full content column
    # This index fails when content exceeds ~2700 bytes (btree limit)
    if index_exists?(:scout_messages, [:session_id, :role, :content, :created_at], name: 'index_scout_messages_duplicate_detection')
      remove_index :scout_messages, name: 'index_scout_messages_duplicate_detection'
    end

    # Create a new index using MD5 hash of content instead
    # This keeps the index size constant regardless of message length
    # MD5 produces 32-character hex string, well within btree limits
    execute <<-SQL
      CREATE INDEX index_scout_messages_duplicate_detection 
      ON scout_messages (session_id, role, md5(content), created_at);
    SQL
  end

  def down
    # Remove the hash-based index
    execute <<-SQL
      DROP INDEX IF EXISTS index_scout_messages_duplicate_detection;
    SQL

    # Recreate the original index (will have same size limit issue)
    add_index :scout_messages, [:session_id, :role, :content, :created_at],
              name: 'index_scout_messages_duplicate_detection'
  end
end
