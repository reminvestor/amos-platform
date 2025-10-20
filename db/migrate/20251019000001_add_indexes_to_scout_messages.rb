class AddIndexesToScoutMessages < ActiveRecord::Migration[8.0]
  def change
    # Add index for session lookup (most common query)
    add_index :scout_messages, [:session_id, :created_at], name: 'index_scout_messages_on_session_and_created'

    # Add index for user messages lookup
    add_index :scout_messages, [:user_id, :session_id], name: 'index_scout_messages_on_user_and_session'

    # Add index for role filtering
    add_index :scout_messages, [:session_id, :role], name: 'index_scout_messages_on_session_and_role'

    # Add index to help detect duplicates
    add_index :scout_messages, [:session_id, :role, :content, :created_at],
              name: 'index_scout_messages_duplicate_detection',
              length: { content: 100 }
  end
end
