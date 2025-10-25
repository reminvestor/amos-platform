# VoiceSession tracks voice assistant conversations
#
# Fields:
# - session_id: UUID for client-side tracking
# - status: active, paused, ended
# - context: JSON hash for keywords, contact names, custom vocabulary
# - transcript_history: JSON array of conversation turns
# - metadata: JSON hash for additional session data
# - started_at: When session began
# - ended_at: When session concluded
class VoiceSession < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  # Status values
  STATUSES = %w[active paused ended].freeze

  # Validations
  validates :session_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  # JSONB fields can be empty but not nil
  validate :context_not_nil
  validate :transcript_history_not_nil
  validate :metadata_not_nil

  # Callbacks
  before_validation :generate_session_id, on: :create
  before_validation :set_started_at, on: :create
  before_validation :initialize_json_fields, on: :create

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :paused, -> { where(status: "paused") }
  scope :ended, -> { where(status: "ended") }
  scope :recent, -> { order(started_at: :desc) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }

  # Instance methods

  def active?
    status == "active"
  end

  def paused?
    status == "paused"
  end

  def ended?
    status == "ended"
  end

  def add_transcript(role:, content:, timestamp: Time.current)
    self.transcript_history ||= []
    self.transcript_history << {
      role: role, # 'user' or 'assistant'
      content: content,
      timestamp: timestamp.iso8601
    }
    save!
  end

  def add_context(key, value)
    self.context ||= {}
    self.context[key] = value
    save!
  end

  def pause!
    update!(status: "paused")
  end

  def resume!
    update!(status: "active")
  end

  def end_session!
    update!(status: "ended", ended_at: Time.current)
  end

  def duration
    return nil unless started_at
    end_time = ended_at || Time.current
    end_time - started_at
  end

  def keywords
    context&.dig("keywords") || []
  end

  def add_keyword(keyword)
    self.context ||= {}
    self.context["keywords"] ||= []
    self.context["keywords"] << keyword unless self.context["keywords"].include?(keyword)
    save!
  end

  private

  def generate_session_id
    self.session_id ||= SecureRandom.uuid
  end

  def set_started_at
    self.started_at ||= Time.current
  end

  def initialize_json_fields
    self.context ||= {}
    self.transcript_history ||= []
    self.metadata ||= {}
    self.status ||= "active"
  end

  def context_not_nil
    errors.add(:context, "can't be nil") if context.nil?
  end

  def transcript_history_not_nil
    errors.add(:transcript_history, "can't be nil") if transcript_history.nil?
  end

  def metadata_not_nil
    errors.add(:metadata, "can't be nil") if metadata.nil?
  end
end
