# frozen_string_literal: true

class SystemNotification < ApplicationRecord
  belongs_to :entity
  belongs_to :user, optional: true
  
  # Validations
  validates :category, presence: true, inclusion: { 
    in: SystemNotificationService::CATEGORIES,
    message: '%{value} is not a valid category'
  }
  validates :severity, presence: true, inclusion: { 
    in: %w[info warning error critical],
    message: '%{value} is not a valid severity'
  }
  validates :title, presence: true, length: { maximum: 255 }
  validates :message, length: { maximum: 5000 }
  
  # Enums
  enum :severity, { info: 'info', warning: 'warning', error: 'error', critical: 'critical' }, prefix: true
  
  # Scopes
  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :not_dismissed, -> { where(dismissed_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :critical_and_errors, -> { where(severity: %w[critical error]) }
  scope :for_user, ->(user) { where(user: user).or(where(user: nil)) }
  scope :by_category, ->(category) { where(category: category) }
  scope :since, ->(time) { where('created_at > ?', time) }
  
  # Callbacks
  after_create :update_unread_count_cache
  after_update :update_unread_count_cache, if: :saved_change_to_read_at?
  
  # Instance methods
  def read?
    read_at.present?
  end
  
  def unread?
    read_at.nil?
  end
  
  def mark_as_read!
    update!(read_at: Time.current) if unread?
  end
  
  def dismiss!(by: nil)
    update!(dismissed_at: Time.current, dismissed_by: by)
  end
  
  def dismissed?
    dismissed_at.present?
  end
  
  def severity_icon
    case severity
    when 'critical' then '🚨'
    when 'error' then '❌'
    when 'warning' then '⚠️'
    else 'ℹ️'
    end
  end
  
  def severity_color
    case severity
    when 'critical' then 'danger'
    when 'error' then 'danger'
    when 'warning' then 'warning'
    else 'info'
    end
  end
  
  def age_in_words
    return 'just now' if created_at > 1.minute.ago
    return "#{((Time.current - created_at) / 60).round}m ago" if created_at > 1.hour.ago
    return "#{((Time.current - created_at) / 3600).round}h ago" if created_at > 1.day.ago
    created_at.strftime('%b %d, %I:%M %p')
  end
  
  # Class methods
  def self.unread_count_for(entity:, user: nil)
    scope = where(entity: entity, read_at: nil)
    scope = scope.where(user: [user, nil]) if user
    scope.count
  end
  
  def self.recent_for(entity:, user: nil, limit: 20)
    scope = where(entity: entity).not_dismissed.recent.limit(limit)
    scope = scope.for_user(user) if user
    scope
  end
  
  private
  
  def update_unread_count_cache
    # Update cached count in Rails cache for fast badge display
    cache_key = "notifications_unread_#{entity_id}_#{user_id || 'all'}"
    count = SystemNotification.where(entity: entity, read_at: nil)
    count = count.where(user: [user, nil]) if user
    Rails.cache.write(cache_key, count.count, expires_in: 5.minutes)
  end
end

