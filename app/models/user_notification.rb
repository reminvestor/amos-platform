# frozen_string_literal: true

# == Schema Information
#
# Table name: user_notifications
#
#  id                    :bigint           not null, primary key
#  entity_id             :bigint           not null
#  user_id               :bigint           not null
#  agent_work_item_id    :bigint
#  scheduled_task_run_id :bigint
#  notification_type     :string           not null
#  title                 :string           not null
#  body                  :text
#  icon                  :string
#  channel               :string           not null
#  email_sent            :boolean          default(FALSE)
#  email_sent_at         :datetime
#  push_sent             :boolean          default(FALSE)
#  push_sent_at          :datetime
#  read                  :boolean          default(FALSE)
#  read_at               :datetime
#  dismissed             :boolean          default(FALSE)
#  dismissed_at          :datetime
#  action_url            :string
#  action_type           :string
#  action_data           :jsonb            default({})
#  priority              :string           default("normal")
#  expires_at            :datetime
#  metadata              :jsonb            default({})
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
class UserNotification < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :agent_work_item, optional: true
  belongs_to :scheduled_task_run, optional: true
  
  # Validations
  validates :notification_type, presence: true, inclusion: { 
    in: %w[
      task_completed task_failed action_required daily_digest weekly_summary
      agent_message asset_created scheduled_reminder system_alert
      collaboration_request work_completed
    ]
  }
  validates :title, presence: true
  validates :channel, presence: true, inclusion: { in: %w[in_app email both] }
  validates :priority, presence: true, inclusion: { in: %w[low normal high urgent] }
  
  # Scopes
  scope :for_user, ->(user) { where(user: user) }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :unread, -> { where(read: false) }
  scope :read, -> { where(read: true) }
  scope :not_dismissed, -> { where(dismissed: false) }
  scope :dismissed, -> { where(dismissed: true) }
  scope :active, -> { not_dismissed.where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :by_priority, ->(priority) { where(priority: priority) }
  scope :urgent, -> { where(priority: 'urgent') }
  scope :needs_email, -> { where(channel: %w[email both]).where(email_sent: false) }
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where('created_at >= ?', Time.current.beginning_of_day) }
  
  # Callbacks
  after_create :broadcast_notification
  after_create :send_email_if_needed
  
  # Notification type configurations
  NOTIFICATION_TYPES = {
    'task_completed' => { icon: '✅', color: 'success' },
    'task_failed' => { icon: '❌', color: 'danger' },
    'action_required' => { icon: '⚠️', color: 'warning' },
    'daily_digest' => { icon: '📋', color: 'info' },
    'weekly_summary' => { icon: '📊', color: 'info' },
    'agent_message' => { icon: '🤖', color: 'primary' },
    'asset_created' => { icon: '🏗️', color: 'success' },
    'scheduled_reminder' => { icon: '⏰', color: 'warning' },
    'system_alert' => { icon: '🔔', color: 'danger' },
    'collaboration_request' => { icon: '🤝', color: 'primary' },
    'work_completed' => { icon: '✨', color: 'success' }
  }.freeze
  
  # Instance methods
  def mark_as_read!
    return if read?
    update!(read: true, read_at: Time.current)
  end
  
  def mark_as_unread!
    update!(read: false, read_at: nil)
  end
  
  def dismiss!
    update!(dismissed: true, dismissed_at: Time.current)
  end
  
  def expired?
    expires_at.present? && expires_at < Time.current
  end
  
  def display_icon
    icon.presence || NOTIFICATION_TYPES.dig(notification_type, :icon) || '📬'
  end
  
  def color_class
    NOTIFICATION_TYPES.dig(notification_type, :color) || 'secondary'
  end
  
  def time_ago
    seconds = (Time.current - created_at).to_i
    
    case seconds
    when 0..59 then "just now"
    when 60..3599 then "#{seconds / 60}m ago"
    when 3600..86399 then "#{seconds / 3600}h ago"
    when 86400..604799 then "#{seconds / 86400}d ago"
    else created_at.strftime('%b %d')
    end
  end
  
  # Class methods
  def self.unread_count_for(user)
    for_user(user).active.unread.count
  end
  
  def self.urgent_count_for(user)
    for_user(user).active.unread.urgent.count
  end
  
  def self.create_for_work_item(work_item, type: 'work_completed')
    create!(
      entity: work_item.entity,
      user: work_item.user,
      agent_work_item: work_item,
      notification_type: type,
      title: work_item.title,
      body: work_item.summary,
      icon: work_item.icon,
      channel: 'in_app',
      priority: work_item.priority,
      action_url: "/scout?view=inbox&item_id=#{work_item.id}",
      action_type: 'view'
    )
  end
  
  def self.create_daily_digest(user, entity, summary)
    create!(
      entity: entity,
      user: user,
      notification_type: 'daily_digest',
      title: "Your Daily Summary",
      body: summary,
      icon: '📋',
      channel: 'both',
      priority: 'normal',
      action_url: '/scout?view=inbox',
      action_type: 'view',
      expires_at: 1.day.from_now
    )
  end
  
  private
  
  def broadcast_notification
    ActionCable.server.broadcast(
      "user_#{user_id}_notifications",
      {
        type: 'new_notification',
        notification: {
          id: id,
          notification_type: notification_type,
          title: title,
          body: body,
          icon: display_icon,
          priority: priority,
          action_url: action_url,
          created_at: created_at.iso8601
        }
      }
    )
  end
  
  def send_email_if_needed
    return unless channel.in?(%w[email both])
    return if email_sent?
    
    # Queue email delivery
    # TODO: Implement NotificationMailer
    # NotificationMailer.notification_email(self).deliver_later
    
    Rails.logger.info "Would send notification email to #{user.email}: #{title}"
  end
end

