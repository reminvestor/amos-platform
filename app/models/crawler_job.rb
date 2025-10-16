class CrawlerJob < ApplicationRecord
  belongs_to :user
  belongs_to :entity
  has_many :crawler_job_logs, dependent: :destroy
  has_many :crawler_conversations, -> { order(timestamp: :asc) }, dependent: :destroy

  # Status validations/scopes/methods could go here

  # Add status validation
  validates :status, inclusion: { in: %w[pending generating ready failed running testing improving fixing] }, allow_nil: true
  validates :description, presence: true

  # Simple helper to add a log entry
  def add_log(message, level = "info")
    CrawlerJobLog.log(self, message, level)
  end

  # Return conversation history in a format suitable for the chat UI
  def conversation_history_json
    # Get all conversations, not just the most recent 50
    conversations = crawler_conversations.order(timestamp: :asc).to_a

    # If no conversations yet, return an empty array
    return [].to_json if conversations.empty?

    # Format for the UI with proper error handling
    conversations.map do |convo|
      begin
        {
          role: convo.role,
          content: convo.content || "", # Ensure we have at least an empty string
          timestamp: convo.timestamp.iso8601
        }
      rescue => e
        # Add a log entry for the error but don't break the UI
        CrawlerJobLog.log(self, "Error formatting conversation history: #{e.message}", "error")
        # Return a placeholder for the problematic message
        {
          role: convo.role || "system",
          content: "[Message could not be displayed]",
          timestamp: Time.current.iso8601
        }
      end
    end.to_json
  end

  # Add a message to the conversation
  def add_message(role, content)
    crawler_conversations.create!(
      role: role,
      content: content,
      timestamp: Time.current
    )
  end

  # Reset the conversation
  def reset_conversation
    crawler_conversations.destroy_all
  end
end
