# frozen_string_literal: true

# PendingToolConfirmation - Stores tool actions awaiting user confirmation
#
# When a tool execution requires user confirmation (per CaMeL security policies),
# the action is stored here until the user confirms or denies it.
#
class PendingToolConfirmation < ApplicationRecord
  belongs_to :entity
  belongs_to :user

  STATUSES = %w[pending confirmed denied expired].freeze

  validates :confirmation_id, presence: true, uniqueness: true
  validates :tool_name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :not_expired, -> { where('expires_at > ?', Time.current) }
  scope :active, -> { pending.not_expired }

  before_validation :set_defaults, on: :create

  def confirm!
    update!(status: 'confirmed', resolved_at: Time.current)
  end

  def deny!
    update!(status: 'denied', resolved_at: Time.current)
  end

  def expire!
    update!(status: 'expired', resolved_at: Time.current)
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def pending?
    status == 'pending' && !expired?
  end

  # Execute the stored tool action
  # @param tool_service [ScoutGenericToolsServiceV2] The service to execute with
  # @return [Hash] Tool execution result
  def execute_with(tool_service)
    return { success: false, error: 'Already resolved' } unless pending?
    return { success: false, error: 'Expired' } if expired?

    confirm!
    
    # Record that this was confirmed (for caching)
    ToolPolicyService.record_confirmation(
      entity: entity,
      user: user,
      tool_name: tool_name,
      args: tool_args
    )
    
    # Execute the tool
    tool_service.execute_tool_by_name(tool_name, tool_args.symbolize_keys)
  end

  private

  def set_defaults
    self.confirmation_id ||= SecureRandom.uuid
    self.expires_at ||= 5.minutes.from_now
    self.status ||= 'pending'
  end
end
