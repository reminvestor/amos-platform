# MemoryBookmark
#
# User-saved conversation points that can be revisited later.
# Enables users to:
# - Save important outputs/responses
# - Share specific conversations
# - Jump back to specific context points
#
class MemoryBookmark < ApplicationRecord
  belongs_to :user
  belongs_to :entity
  belongs_to :scout_message
  belongs_to :agent_work_item, optional: true

  BOOKMARK_TYPES = %w[saved milestone shared favorite].freeze

  validates :title, presence: true
  validates :bookmark_type, inclusion: { in: BOOKMARK_TYPES }

  scope :for_user_entity, ->(user, entity) { where(user: user, entity: entity) }
  scope :shareable, -> { where(shareable: true) }
  scope :by_recency, -> { order(created_at: :desc) }

  before_create :generate_share_token

  # Find by share token (for public access)
  def self.find_by_share_token(token)
    find_by(share_token: token, shareable: true)
  end

  # Mark as shared
  def share!
    update!(
      shareable: true,
      shared_at: Time.current,
      share_token: share_token || SecureRandom.urlsafe_base64(16)
    )
    share_url
  end

  def unshare!
    update!(shareable: false)
  end

  def share_url
    return nil unless shareable && share_token
    "/shared/#{share_token}"
  end

  # Record a view
  def record_view!
    increment!(:view_count)
  end

  # Get context messages
  def context_messages
    return [] if context_snapshot.blank?
    JSON.parse(context_snapshot)
  rescue JSON::ParserError
    []
  end

  # Format for API response
  def to_api_hash
    {
      id: id,
      title: title,
      description: description,
      type: bookmark_type,
      created_at: created_at.iso8601,
      message_preview: scout_message&.content&.truncate(200),
      shareable: shareable,
      share_url: share_url,
      view_count: view_count
    }
  end

  private

  def generate_share_token
    self.share_token ||= SecureRandom.urlsafe_base64(16) if shareable
  end
end
