# MemoryBookmark
#
# Scout-user memory system for saving important context and conversations.
# This is SEPARATE from Work Items (which is the agent inbox for documents/exports).
#
# Bookmarks are for:
# - Conversations - key exchanges worth saving
# - Context blocks - pieces of info/data to reference later  
# - Insights - important learnings Scout should remember
# - Responses - specific Scout outputs the user wants to keep
#
# NOT for documents/exports - those go to AgentWorkItem (the agent inbox)
#
class MemoryBookmark < ApplicationRecord
  belongs_to :user
  belongs_to :entity
  belongs_to :scout_message, optional: true  # Not all bookmarks come from messages

  # Bookmark intent/purpose
  BOOKMARK_TYPES = %w[saved milestone shared favorite reference].freeze
  
  # What kind of content is being bookmarked (Scout-user focused)
  CONTENT_TYPES = %w[
    conversation
    context_block
    insight
    response
    visualization
  ].freeze

  # Content type icons for UI
  CONTENT_TYPE_ICONS = {
    'conversation' => 'message-square',
    'context_block' => 'box',
    'insight' => 'lightbulb',
    'response' => 'message-circle',
    'visualization' => 'bar-chart-2'
  }.freeze

  validates :title, presence: true
  validates :bookmark_type, inclusion: { in: BOOKMARK_TYPES }
  validates :content_type, inclusion: { in: CONTENT_TYPES }, allow_nil: true

  scope :for_user_entity, ->(user, entity) { where(user: user, entity: entity) }
  scope :shareable, -> { where(shareable: true) }
  scope :by_recency, -> { order(created_at: :desc) }
  scope :by_content_type, ->(type) { where(content_type: type) }
  scope :conversations, -> { where(content_type: 'conversation') }
  scope :visualizations, -> { where(content_type: 'visualization') }
  scope :context_blocks, -> { where(content_type: 'context_block') }
  scope :insights, -> { where(content_type: 'insight') }

  before_create :generate_share_token
  before_create :set_defaults

  # Find by share token (for public access)
  def self.find_by_share_token(token)
    find_by(share_token: token, shareable: true)
  end

  # Create a context block bookmark
  def self.create_context_block(user:, entity:, title:, content:, description: nil, tags: [])
    create!(
      user: user,
      entity: entity,
      title: title,
      description: description,
      content_type: 'context_block',
      bookmark_type: 'saved',
      source: 'user',
      content: content.is_a?(Hash) ? content : { text: content },
      tags: tags
    )
  end

  # Create a visualization bookmark
  def self.create_visualization(user:, entity:, title:, visualization_data:, description: nil)
    create!(
      user: user,
      entity: entity,
      title: title,
      description: description,
      content_type: 'visualization',
      bookmark_type: 'saved',
      source: 'tool',
      content: visualization_data
    )
  end

  # Create an insight bookmark
  def self.create_insight(user:, entity:, title:, insight:, description: nil, tags: [])
    create!(
      user: user,
      entity: entity,
      title: title,
      description: description,
      content_type: 'insight',
      bookmark_type: 'saved',
      source: 'scout',
      content: insight.is_a?(Hash) ? insight : { text: insight },
      tags: tags
    )
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

  # Get context messages (for conversation bookmarks)
  def context_messages
    return [] if context_snapshot.blank?
    JSON.parse(context_snapshot)
  rescue JSON::ParserError
    []
  end

  # Get the content hash
  def content_data
    return {} if content.blank?
    content.is_a?(String) ? JSON.parse(content) : content
  rescue JSON::ParserError
    {}
  end

  # Get icon for this bookmark type
  def icon
    CONTENT_TYPE_ICONS[content_type] || 'bookmark'
  end

  # Format for API response
  def to_api_hash
    {
      id: id,
      title: title,
      description: description,
      type: bookmark_type,
      content_type: content_type,
      icon: icon,
      created_at: created_at.iso8601,
      message_preview: scout_message&.content&.truncate(200),
      content: content_data,
      tags: tags || [],
      shareable: shareable,
      share_url: share_url,
      view_count: view_count,
      source: source
    }
  end

  private

  def generate_share_token
    self.share_token ||= SecureRandom.urlsafe_base64(16) if shareable
  end

  def set_defaults
    self.content_type ||= 'conversation'
    self.source ||= 'user'
    self.content ||= {}
    self.tags ||= []
  end
end
