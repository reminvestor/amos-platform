class UserReminder < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :remind_at, presence: true
  validates :priority, inclusion: { in: %w[low normal high] }
  validates :repeat_interval, inclusion: { in: %w[none daily weekly monthly] }, allow_nil: true

  scope :pending, -> { where(completed: false) }
  scope :completed, -> { where(completed: true) }
  scope :upcoming, -> { pending.where('remind_at >= ?', Time.current).order(remind_at: :asc) }
  scope :overdue, -> { pending.where('remind_at < ?', Time.current).order(remind_at: :asc) }
  scope :today, -> { pending.where(remind_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :this_week, -> { pending.where(remind_at: Time.current.beginning_of_week..Time.current.end_of_week) }
  scope :high_priority, -> { where(priority: 'high') }

  def complete!
    update!(completed: true, completed_at: Time.current)
  end

  def uncomplete!
    update!(completed: false, completed_at: nil)
  end

  def mark_notified!
    update!(notified: true, notified_at: Time.current)
  end

  def overdue?
    !completed? && remind_at < Time.current
  end

  def due_today?
    remind_at.to_date == Date.current
  end

  def priority_class
    case priority
    when 'high' then 'text-danger'
    when 'low' then 'text-muted'
    else 'text-primary'
    end
  end

  def priority_icon
    case priority
    when 'high' then 'alert-circle'
    when 'low' then 'minus-circle'
    else 'circle'
    end
  end
end
