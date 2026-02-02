# frozen_string_literal: true

# ExternalAgentNotification - Notifications for external agents from AMOS
#
# Types:
# - bounty_recommendation: AMOS found a good bounty match
# - trust_upgrade: Agent's trust level increased
# - trust_warning: Agent at risk of trust level decrease
# - policy_update: Tool/policy changes affecting agent
# - system: General system notifications
#
class ExternalAgentNotification < ApplicationRecord
  belongs_to :external_agent_registration

  NOTIFICATION_TYPES = %w[
    bounty_recommendation
    trust_upgrade
    trust_warning
    policy_update
    system
    review_complete
  ].freeze

  ACTION_TYPES = %w[claimed dismissed viewed expired].freeze

  validates :notification_type, presence: true, inclusion: { in: NOTIFICATION_TYPES }
  validates :title, presence: true
  validates :action_taken, inclusion: { in: ACTION_TYPES }, allow_nil: true

  # Scopes
  scope :unread, -> { where(read: false) }
  scope :pending_action, -> { where(actioned: false) }
  scope :recommendations, -> { where(notification_type: 'bounty_recommendation') }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_agent, ->(agent) { where(external_agent_registration: agent) }

  # Mark as read
  def mark_read!
    update!(read: true, read_at: Time.current) unless read?
  end

  # Record action taken
  def record_action!(action)
    update!(
      actioned: true,
      action_taken: action,
      actioned_at: Time.current
    )
  end

  # Check if still actionable (e.g., bounty not claimed by someone else)
  def still_actionable?
    return false if actioned?
    return true unless notification_type == 'bounty_recommendation'
    
    bounty_id = metadata['bounty_id']
    return false unless bounty_id
    
    bounty = Bounty.find_by(id: bounty_id)
    bounty&.status == 'open'
  end

  # API response format
  def to_api_response
    {
      id: id,
      type: notification_type,
      title: title,
      message: message,
      metadata: metadata,
      read: read?,
      actioned: actioned?,
      action_taken: action_taken,
      still_actionable: still_actionable?,
      created_at: created_at.iso8601
    }
  end
end
