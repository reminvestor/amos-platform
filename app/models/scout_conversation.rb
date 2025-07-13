class ScoutConversation < ApplicationRecord
  belongs_to :user
  belongs_to :entity
  
  has_many :business_insights, foreign_key: :source_conversation_id, dependent: :destroy
  has_many :agent_activities, foreign_key: :conversation_id, dependent: :destroy
  
  validates :session_id, presence: true
  validates :message_type, presence: true, inclusion: { in: %w[user assistant] }
  validates :content, presence: true
  
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :user_messages, -> { where(message_type: 'user') }
  scope :assistant_messages, -> { where(message_type: 'assistant') }
  scope :recent, -> { order(created_at: :desc) }
  
  # Get conversation history for a session
  def self.session_history(session_id, limit: 50)
    for_session(session_id).order(created_at: :asc).limit(limit)
  end
  
  # Format message for AI context
  def to_ai_message
    {
      role: message_type,
      content: content,
      timestamp: created_at,
      metadata: metadata
    }
  end
end
