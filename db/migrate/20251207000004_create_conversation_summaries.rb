class CreateConversationSummaries < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_summaries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :session_id, null: false
      
      # Summary content
      t.text :summary, null: false              # The actual summary text
      t.text :key_topics                        # JSON array of main topics discussed
      t.text :key_decisions                     # JSON array of decisions made
      t.text :action_items                      # JSON array of pending action items
      t.text :context_for_future                # What Scout should remember for future
      
      # Coverage tracking
      t.integer :message_start_index, null: false  # First message index summarized
      t.integer :message_end_index, null: false    # Last message index summarized
      t.integer :messages_summarized, null: false  # Count of messages in this summary
      
      # Token efficiency
      t.integer :original_tokens                # Estimated tokens of original messages
      t.integer :summary_tokens                 # Tokens in summary (compression ratio)
      
      # Metadata
      t.string :model_used                      # Which model created the summary
      t.boolean :active, default: true          # Is this summary current?
      
      t.timestamps
    end
    
    add_index :conversation_summaries, :session_id
    add_index :conversation_summaries, [:session_id, :active]
    add_index :conversation_summaries, [:user_id, :entity_id, :session_id]
    add_index :conversation_summaries, :message_end_index
  end
end
