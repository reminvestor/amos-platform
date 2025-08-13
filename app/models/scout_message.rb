class ScoutMessage < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true

  enum :role, { user: 'user', assistant: 'assistant' }

  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :oldest_first, -> { order(created_at: :asc) }
end




