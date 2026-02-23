# frozen_string_literal: true

class Activity < ApplicationRecord
  # Associations
  belongs_to :contact, optional: true
  belongs_to :opportunity, optional: true
  belongs_to :user, optional: true
  belongs_to :performed_by_agent, class_name: 'AgentPlugin', optional: true
  belongs_to :assigned_user, class_name: 'User', optional: true
  belongs_to :assigned_agent, class_name: 'AgentPlugin', optional: true
  belongs_to :entity

  # Activity types with configuration
  ACTIVITY_TYPES = {
    'note' => { icon: 'sticky-note', color: '#6B7280', label: 'Note' },
    'email' => { icon: 'mail', color: '#3B82F6', label: 'Email' },
    'call' => { icon: 'phone', color: '#10B981', label: 'Call' },
    'meeting' => { icon: 'calendar', color: '#8B5CF6', label: 'Meeting' },
    'task' => { icon: 'check-square', color: '#F59E0B', label: 'Task' },
    'form_submission' => { icon: 'file-text', color: '#EC4899', label: 'Form Submission' },
    'ai_action' => { icon: 'bot', color: '#06B6D4', label: 'AI Action' },
    'stage_change' => { icon: 'git-branch', color: '#8B5CF6', label: 'Stage Change' },
    'assignment' => { icon: 'user-plus', color: '#F97316', label: 'Assignment' },
    'opportunity_created' => { icon: 'briefcase', color: '#10B981', label: 'Opportunity Created' },
    'email_sent' => { icon: 'send', color: '#3B82F6', label: 'Email Sent' },
    'email_opened' => { icon: 'mail-open', color: '#22D3EE', label: 'Email Opened' },
    'email_clicked' => { icon: 'mouse-pointer', color: '#A855F7', label: 'Email Clicked' },
    'email_bounced' => { icon: 'mail-x', color: '#EF4444', label: 'Email Bounced' },
    'spam_complaint' => { icon: 'alert-triangle', color: '#DC2626', label: 'Spam Complaint' },
    'page_view' => { icon: 'eye', color: '#64748B', label: 'Page View' }
  }.freeze

  STATUSES = %w[pending in_progress completed cancelled].freeze
  PRIORITIES = %w[low normal high urgent].freeze

  attribute :status, :string, default: "pending"
  attribute :priority, :string, default: "normal"
  attribute :activity_type, :string, default: "note"
  
  CALL_OUTCOMES = %w[connected voicemail no_answer busy callback_scheduled left_message].freeze
  MEETING_OUTCOMES = %w[completed rescheduled cancelled no_show].freeze

  # Validations
  validates :activity_type, presence: true, inclusion: { in: ACTIVITY_TYPES.keys }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true
  validate :must_have_contact_or_opportunity
  validate :validate_outcome_for_type

  # Scopes
  scope :by_type, ->(type) { where(activity_type: type) }
  scope :by_entity, ->(entity) { where(entity: entity) }
  scope :by_status, ->(status) { where(status: status) }
  scope :pending, -> { where(status: 'pending') }
  scope :in_progress, -> { where(status: 'in_progress') }
  scope :completed, -> { where(status: 'completed') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :open, -> { where(status: ['pending', 'in_progress']) }
  scope :tasks, -> { where(activity_type: 'task') }
  scope :notes, -> { where(activity_type: 'note') }
  scope :calls, -> { where(activity_type: 'call') }
  scope :meetings, -> { where(activity_type: 'meeting') }
  scope :emails, -> { where(activity_type: ['email', 'email_sent', 'email_opened', 'email_clicked']) }
  scope :ai_activities, -> { where(activity_type: 'ai_action').or(where.not(performed_by_agent_id: nil)) }
  scope :human_activities, -> { where(performed_by_agent_id: nil) }
  scope :overdue, -> { open.where('due_at < ?', Time.current) }
  scope :due_today, -> { open.where(due_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :due_this_week, -> { open.where(due_at: Time.current..1.week.from_now) }
  scope :scheduled_today, -> { where(scheduled_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :upcoming, -> { open.where('scheduled_at > ?', Time.current).order(scheduled_at: :asc) }
  scope :recent, -> { order(created_at: :desc) }
  scope :timeline, -> { order(created_at: :desc) }
  scope :assigned_to_user, ->(user) { where(assigned_user: user) }
  scope :assigned_to_agent, ->(agent) { where(assigned_agent: agent) }
  scope :unassigned, -> { where(assigned_user_id: nil, assigned_agent_id: nil) }
  scope :for_contact, ->(contact) { where(contact: contact) }
  scope :for_opportunity, ->(opp) { where(opportunity: opp) }

  # Callbacks
  before_validation :set_defaults
  after_save :update_contact_last_activity
  after_create :create_work_item_if_needed

  # Status transition methods
  def start!
    return false unless pending?
    update!(status: 'in_progress')
  end

  def complete!(outcome: nil)
    update!(
      status: 'completed',
      completed_at: Time.current,
      outcome: outcome
    )
  end

  def cancel!(reason: nil)
    update!(
      status: 'cancelled',
      metadata: metadata.merge('cancel_reason' => reason)
    )
  end

  def reschedule!(new_time)
    update!(
      scheduled_at: new_time,
      metadata: metadata.merge('rescheduled_from' => scheduled_at&.iso8601)
    )
  end

  # Status checks
  def pending?
    status == 'pending'
  end

  def in_progress?
    status == 'in_progress'
  end

  def completed?
    status == 'completed'
  end

  def cancelled?
    status == 'cancelled'
  end

  def open?
    status.in?(['pending', 'in_progress'])
  end

  def overdue?
    open? && due_at.present? && due_at < Time.current
  end

  def due_soon?(hours = 24)
    open? && due_at.present? && due_at <= hours.hours.from_now
  end

  # Assignment methods
  def assign_to_user!(user)
    update!(assigned_user: user, assigned_agent: nil)
  end

  def assign_to_agent!(agent)
    update!(assigned_agent: agent, assigned_user: nil)
  end

  def assigned?
    assigned_user_id.present? || assigned_agent_id.present?
  end

  def assigned_to
    assigned_user || assigned_agent
  end

  def assigned_name
    if assigned_user.present?
      assigned_user.full_name
    elsif assigned_agent.present?
      "AI: #{assigned_agent.name}"
    else
      'Unassigned'
    end
  end

  # Performer info
  def performed_by
    user || performed_by_agent
  end

  def performer_name
    if user.present?
      user.full_name
    elsif performed_by_agent.present?
      "AI: #{performed_by_agent.name}"
    else
      'System'
    end
  end

  def ai_performed?
    performed_by_agent_id.present?
  end

  # Type helpers
  def type_info
    ACTIVITY_TYPES[activity_type] || {}
  end

  def type_icon
    type_info[:icon] || 'activity'
  end

  def type_color
    type_info[:color] || '#6B7280'
  end

  def type_label
    type_info[:label] || activity_type.titleize
  end

  def is_task?
    activity_type == 'task'
  end

  def is_communication?
    activity_type.in?(['email', 'call', 'meeting', 'email_sent'])
  end

  def is_automated?
    activity_type.in?(['ai_action', 'form_submission', 'email_opened', 'email_clicked', 'page_view'])
  end

  # Factory methods for common activities
  def self.log_note(contact:, entity:, description:, user: nil, agent: nil, opportunity: nil)
    create!(
      contact: contact,
      opportunity: opportunity,
      entity: entity,
      user: user,
      performed_by_agent: agent,
      activity_type: 'note',
      subject: 'Note added',
      description: description,
      status: 'completed',
      completed_at: Time.current
    )
  end

  def self.log_call(contact:, entity:, outcome:, description: nil, user: nil, agent: nil, opportunity: nil, duration_minutes: nil)
    create!(
      contact: contact,
      opportunity: opportunity,
      entity: entity,
      user: user,
      performed_by_agent: agent,
      activity_type: 'call',
      subject: "Call - #{outcome.titleize}",
      description: description,
      outcome: outcome,
      status: 'completed',
      completed_at: Time.current,
      metadata: { duration_minutes: duration_minutes }.compact
    )
  end

  def self.log_email(contact:, entity:, subject:, description: nil, user: nil, agent: nil, opportunity: nil)
    create!(
      contact: contact,
      opportunity: opportunity,
      entity: entity,
      user: user,
      performed_by_agent: agent,
      activity_type: 'email_sent',
      subject: subject,
      description: description,
      status: 'completed',
      completed_at: Time.current
    )
  end

  def self.create_task(contact:, entity:, subject:, description: nil, due_at: nil, priority: 'normal', 
                       assigned_user: nil, assigned_agent: nil, opportunity: nil, user: nil)
    create!(
      contact: contact,
      opportunity: opportunity,
      entity: entity,
      user: user,
      assigned_user: assigned_user,
      assigned_agent: assigned_agent,
      activity_type: 'task',
      subject: subject,
      description: description,
      due_at: due_at,
      priority: priority,
      status: 'pending'
    )
  end

  def self.schedule_meeting(contact:, entity:, subject:, scheduled_at:, description: nil,
                            assigned_user: nil, assigned_agent: nil, opportunity: nil, user: nil)
    create!(
      contact: contact,
      opportunity: opportunity,
      entity: entity,
      user: user,
      assigned_user: assigned_user,
      assigned_agent: assigned_agent,
      activity_type: 'meeting',
      subject: subject,
      description: description,
      scheduled_at: scheduled_at,
      status: 'pending'
    )
  end

  def self.log_ai_action(contact:, entity:, agent:, subject:, description:, opportunity: nil)
    create!(
      contact: contact,
      opportunity: opportunity,
      entity: entity,
      performed_by_agent: agent,
      activity_type: 'ai_action',
      subject: subject,
      description: description,
      status: 'completed',
      completed_at: Time.current
    )
  end

  # Stats methods
  def self.activity_stats(entity, period: 30.days)
    activities = where(entity: entity).where('created_at >= ?', period.ago)
    stats_for(activities)
  end

  def self.stats_for(activities)
    {
      total: activities.count,
      by_type: ACTIVITY_TYPES.keys.each_with_object({}) do |type, hash|
        hash[type] = activities.by_type(type).count
      end,
      open_tasks: activities.tasks.pending.count,
      overdue_tasks: activities.tasks.overdue.count,
      completed_today: activities.completed.where('completed_at >= ?', Time.current.beginning_of_day).count,
      by_performer: {
        human: activities.human_activities.count,
        ai: activities.ai_activities.count
      }
    }
  end

  private

  def set_defaults
    self.priority ||= 'normal'
    self.status ||= activity_type == 'task' ? 'pending' : 'completed'
    self.completed_at ||= Time.current if completed? && completed_at.nil?
  end

  def must_have_contact_or_opportunity
    if contact_id.blank? && opportunity_id.blank?
      errors.add(:base, "Activity must be associated with a contact or opportunity")
    end
  end

  def validate_outcome_for_type
    return unless outcome.present?
    
    case activity_type
    when 'call'
      unless CALL_OUTCOMES.include?(outcome)
        errors.add(:outcome, "must be one of: #{CALL_OUTCOMES.join(', ')}")
      end
    when 'meeting'
      unless MEETING_OUTCOMES.include?(outcome)
        errors.add(:outcome, "must be one of: #{MEETING_OUTCOMES.join(', ')}")
      end
    end
  end

  def update_contact_last_activity
    return unless contact.present?
    
    # Update contact's last activity timestamp
    contact.update_column(:last_activity_at, Time.current)
    
    # Update last_contacted_at for communication activities
    if is_communication? && completed?
      contact.update_column(:last_contacted_at, Time.current)
    end
  end

  def create_work_item_if_needed
    # Create work item for tasks assigned to users or urgent items
    return unless is_task? && (assigned_user_id.present? || priority == 'urgent')
    
    target_user = assigned_user || contact&.assigned_user || entity.owner
    return unless target_user

    AgentWorkItem.create(
      entity: entity,
      user: target_user,
      work_type: 'action_required',
      title: subject || "New task: #{activity_type.titleize}",
      summary: description&.truncate(200),
      requires_action: true,
      action_type: 'complete_task',
      action_due_at: due_at,
      priority: priority,
      asset_type: 'Activity',
      asset_id: id,
      metadata: {
        activity_type: activity_type,
        contact_id: contact_id,
        opportunity_id: opportunity_id
      }
    )
  rescue => e
    Rails.logger.error "Failed to create work item for activity #{id}: #{e.message}"
  end
end
