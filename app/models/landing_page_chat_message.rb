class LandingPageChatMessage < ApplicationRecord
  belongs_to :landing_page
  belongs_to :user

  validates :content, presence: true
  validates :role, presence: true, inclusion: { in: %w[user assistant system] }

  scope :in_order, -> { order(created_at: :asc) }

  def self.conversation_history(landing_page_id, format: :hash)
    messages = where(landing_page_id: landing_page_id).in_order

    if format == :hash
      messages.map do |msg|
        {
          role: msg.role,
          content: msg.content
        }
      end
    else
      messages
    end
  end
end
