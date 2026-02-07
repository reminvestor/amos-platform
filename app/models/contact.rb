class Contact < ApplicationRecord
  include HasCustomFields
  include AutomationTriggerable
  
  belongs_to :user
  belongs_to :entity

  # CRM Assignments
  belongs_to :assigned_user, class_name: 'User', optional: true
  belongs_to :assigned_agent, class_name: 'AgentPlugin', optional: true

  # Many-to-many association with contact groups
  has_and_belongs_to_many :contact_groups, -> { distinct }, class_name: "ContactGroup"

  # Email sequence associations
  has_many :sequence_enrollments, dependent: :destroy
  has_many :email_sequences, through: :sequence_enrollments

  # CRM associations
  has_many :opportunities, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :landing_page_submissions, dependent: :nullify

  # JSONB metadata handling - Rails 8.0 compatible
  # Note: serialize in Rails 8 now uses different configuration style
  attribute :metadata, :json

  # Lifecycle stages
  LIFECYCLE_STAGES = {
    'subscriber' => { order: 1, label: 'Subscriber', color: '#6B7280' },
    'lead' => { order: 2, label: 'Lead', color: '#3B82F6' },
    'mql' => { order: 3, label: 'Marketing Qualified', color: '#8B5CF6' },
    'sql' => { order: 4, label: 'Sales Qualified', color: '#F59E0B' },
    'opportunity' => { order: 5, label: 'Opportunity', color: '#EC4899' },
    'customer' => { order: 6, label: 'Customer', color: '#10B981' },
    'evangelist' => { order: 7, label: 'Evangelist', color: '#14B8A6' }
  }.freeze

  LEAD_SOURCES = %w[
    landing_page website referral social_media email_campaign 
    cold_outreach event partner import manual other
  ].freeze

  # Helper methods for corporation data
  def corporation_id
    metadata&.dig("corporation_id")
  end

  def corporation_name
    metadata&.dig("corporation_name")
  end

  # Validations
  validates :email, presence: true, email: true
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :lifecycle_stage, inclusion: { in: LIFECYCLE_STAGES.keys }, allow_nil: true
  validates :lead_source, inclusion: { in: LEAD_SOURCES }, allow_blank: true
  validates :lead_score, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Status options
  STATUSES = %w[active inactive unsubscribed bounced].freeze
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  # Scopes
  scope :by_entity, ->(entity_id) { where(entity_id: entity_id) if entity_id.present? }
  scope :global, -> { where(entity_id: nil) }
  # Lead/customer scopes derived from lifecycle_stage (lead boolean is deprecated)
  scope :leads, -> { where(lifecycle_stage: %w[subscriber lead mql]) }
  scope :customers, -> { where(lifecycle_stage: 'customer') }
  
  # CRM Scopes
  scope :by_lifecycle_stage, ->(stage) { where(lifecycle_stage: stage) }
  scope :subscribers, -> { where(lifecycle_stage: 'subscriber') }
  scope :marketing_qualified, -> { where(lifecycle_stage: 'mql') }
  scope :sales_qualified, -> { where(lifecycle_stage: 'sql') }
  scope :in_opportunity, -> { where(lifecycle_stage: 'opportunity') }
  scope :converted_customers, -> { where(lifecycle_stage: 'customer') }
  scope :evangelists, -> { where(lifecycle_stage: 'evangelist') }
  
  scope :assigned_to_user, ->(user) { where(assigned_user: user) }
  scope :assigned_to_agent, ->(agent) { where(assigned_agent: agent) }
  scope :unassigned, -> { where(assigned_user_id: nil, assigned_agent_id: nil) }
  
  scope :high_score, ->(min = 50) { where('lead_score >= ?', min) }
  scope :needs_follow_up, -> { where('next_follow_up_at <= ?', Time.current) }
  scope :recently_active, ->(days = 7) { where('last_activity_at >= ?', days.days.ago) }
  scope :inactive, ->(days = 30) { where('last_activity_at < ? OR last_activity_at IS NULL', days.days.ago) }
  scope :by_source, ->(source) { where(lead_source: source) }
  scope :converted, -> { where.not(converted_at: nil) }
  scope :not_converted, -> { where(converted_at: nil) }

  # Methods
  def full_name
    "#{first_name} #{last_name}"
  end

  # Lifecycle stage methods
  def lifecycle_stage_info
    LIFECYCLE_STAGES[lifecycle_stage] || {}
  end

  def lifecycle_stage_label
    lifecycle_stage_info[:label] || lifecycle_stage&.titleize || 'Unknown'
  end

  def lifecycle_stage_color
    lifecycle_stage_info[:color] || '#6B7280'
  end

  def lifecycle_stage_order
    lifecycle_stage_info[:order] || 0
  end

  def promote_lifecycle!(new_stage, source: nil)
    return false unless LIFECYCLE_STAGES.key?(new_stage)
    
    current_order = lifecycle_stage_order
    new_order = LIFECYCLE_STAGES[new_stage][:order]
    
    # Only allow forward progression (or any change if forced)
    return false if new_order <= current_order && source != 'force'
    
    old_stage = lifecycle_stage
    update!(lifecycle_stage: new_stage)
    
    # Log the promotion as an activity
    activities.create!(
      entity: entity,
      activity_type: 'stage_change',
      subject: "Lifecycle stage changed to #{LIFECYCLE_STAGES[new_stage][:label]}",
      description: "Promoted from #{LIFECYCLE_STAGES[old_stage][:label]} to #{LIFECYCLE_STAGES[new_stage][:label]}",
      status: 'completed',
      completed_at: Time.current,
      metadata: { old_stage: old_stage, new_stage: new_stage, source: source }
    )
    
    true
  end

  def mark_as_customer!(source: nil)
    update!(
      lifecycle_stage: 'customer',
      converted_at: Time.current,
      conversion_source: source
    )
  end

  # Deprecated: use lifecycle_stage instead. Kept for backward compatibility.
  def lead?
    lifecycle_stage.in?(%w[subscriber lead mql])
  end

  # Assignment methods
  def assign_to_user!(user)
    update!(assigned_user: user, assigned_agent: nil)
    activities.create!(
      entity: entity,
      user: user,
      activity_type: 'assignment',
      subject: "Assigned to #{user.full_name}",
      status: 'completed',
      completed_at: Time.current
    )
  end

  def assign_to_agent!(agent)
    update!(assigned_agent: agent, assigned_user: nil)
    activities.create!(
      entity: entity,
      performed_by_agent: agent,
      activity_type: 'assignment',
      subject: "Assigned to AI Agent: #{agent.name}",
      status: 'completed',
      completed_at: Time.current
    )
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

  # Lead scoring methods
  def adjust_lead_score!(delta, reason: nil, metadata: {})
    new_score = [(lead_score || 0) + delta, 0].max
    update!(lead_score: new_score)

    # Log significant score changes
    if delta.abs >= 10
      activity_metadata = { old_score: lead_score - delta, new_score: new_score, delta: delta }
      activity_metadata.merge!(metadata) if metadata.present?
      
      activities.create!(
        entity: entity,
        activity_type: 'ai_action',
        subject: "Lead score #{delta > 0 ? 'increased' : 'decreased'} by #{delta.abs}",
        description: reason,
        status: 'completed',
        completed_at: Time.current,
        metadata: activity_metadata
      )
    end
    
    # Auto-promote to MQL if score crosses threshold
    if new_score >= 50 && lifecycle_stage == 'lead'
      promote_lifecycle!('mql', source: 'lead_score')
    end
    
    new_score
  end

  def high_value?
    (lead_score || 0) >= 50
  end

  # Activity helpers
  def timeline
    activities.timeline.limit(50)
  end

  def open_tasks
    activities.tasks.open
  end

  def last_activity
    activities.order(created_at: :desc).first
  end

  def days_since_last_contact
    return nil unless last_contacted_at
    (Date.current - last_contacted_at.to_date).to_i
  end

  def needs_follow_up?
    next_follow_up_at.present? && next_follow_up_at <= Time.current
  end

  def schedule_follow_up!(at:, user: nil, agent: nil, subject: nil)
    update!(next_follow_up_at: at)
    
    Activity.create_task(
      contact: self,
      entity: entity,
      subject: subject || "Follow up with #{full_name}",
      due_at: at,
      assigned_user: user,
      assigned_agent: agent,
      user: user
    )
  end

  # Opportunity helpers
  def open_opportunities
    opportunities.open
  end

  def total_opportunity_value
    opportunities.open.sum(:value) || 0
  end

  def has_won_opportunity?
    opportunities.won.exists?
  end

  # Quick action methods for Scout
  def log_note!(description, user: nil, agent: nil)
    Activity.log_note(contact: self, entity: entity, description: description, user: user, agent: agent)
  end

  def log_call!(outcome:, description: nil, user: nil, agent: nil, duration_minutes: nil)
    Activity.log_call(
      contact: self, 
      entity: entity, 
      outcome: outcome, 
      description: description, 
      user: user, 
      agent: agent,
      duration_minutes: duration_minutes
    )
  end

  def log_email!(subject:, description: nil, user: nil, agent: nil)
    Activity.log_email(contact: self, entity: entity, subject: subject, description: description, user: user, agent: agent)
  end

  def create_opportunity!(name:, value: nil, source: nil, user: nil, agent: nil)
    opportunities.create!(
      entity: entity,
      user: user,
      assigned_agent: agent,
      name: name,
      value: value,
      source: source || lead_source || 'direct',
      stage: 'lead'
    )
  end

  # Callbacks
  before_save :ensure_single_group
  before_validation :set_default_lifecycle_stage

  private

  def set_default_lifecycle_stage
    # DB default is 'subscriber' but platform default for AI-created contacts should be 'lead'
    # Only override if it's the DB default (subscriber) and this is a new record
    self.lifecycle_stage = 'lead' if new_record? && lifecycle_stage == 'subscriber'
    self.status ||= 'active'
  end

  def single_group_membership
    return unless contact_groups.size > 1
    errors.add(:contact_groups, "can only belong to one group at a time")
  end

  def ensure_single_group
    # Group by entity_id
    entity_groups = contact_groups.group_by(&:entity_id)

    # For each entity, ensure there's only one group
    entity_groups.each do |ent_id, groups|
      next unless groups.size > 1

      # Keep only the most recent group for this entity
      latest_group = groups.sort_by(&:updated_at).last
      groups_to_remove = groups - [ latest_group ]

      # Remove all but the latest group
      self.contact_groups.delete(groups_to_remove)
    end
  end
end
