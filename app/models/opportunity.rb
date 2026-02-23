# frozen_string_literal: true

class Opportunity < ApplicationRecord
  include HasCustomFields
  
  # Associations
  belongs_to :contact
  belongs_to :user
  belongs_to :entity
  belongs_to :assigned_agent, class_name: 'AgentPlugin', optional: true
  
  has_many :activities, dependent: :destroy

  # Pipeline stages with probabilities
  STAGES = {
    'lead' => { probability: 10, order: 1, label: 'Lead', color: '#6B7280' },
    'qualified' => { probability: 25, order: 2, label: 'Qualified', color: '#3B82F6' },
    'proposal' => { probability: 50, order: 3, label: 'Proposal', color: '#8B5CF6' },
    'negotiation' => { probability: 75, order: 4, label: 'Negotiation', color: '#F59E0B' },
    'closed_won' => { probability: 100, order: 5, label: 'Closed Won', color: '#10B981' },
    'closed_lost' => { probability: 0, order: 6, label: 'Closed Lost', color: '#EF4444' }
  }.freeze

  SOURCES = %w[landing_page referral direct website email social_media cold_outreach partner other].freeze

  LOST_REASONS = %w[
    price competitor no_budget timing no_decision lost_contact 
    product_fit went_silent other
  ].freeze

  attribute :stage, :string, default: "lead"

  # Validations
  validates :name, presence: true
  validates :stage, presence: true, inclusion: { in: STAGES.keys }
  validates :probability, numericality: { 
    only_integer: true, 
    greater_than_or_equal_to: 0, 
    less_than_or_equal_to: 100 
  }, allow_nil: true
  validates :value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }, allow_blank: true
  validates :lost_reason, inclusion: { in: LOST_REASONS }, allow_blank: true
  validate :lost_reason_required_when_closed_lost
  validate :close_date_required_when_closed

  # Scopes
  scope :open, -> { where.not(stage: ['closed_won', 'closed_lost']) }
  scope :closed, -> { where(stage: ['closed_won', 'closed_lost']) }
  scope :won, -> { where(stage: 'closed_won') }
  scope :lost, -> { where(stage: 'closed_lost') }
  scope :by_stage, ->(stage) { where(stage: stage) }
  scope :by_entity, ->(entity) { where(entity: entity) }
  scope :by_user, ->(user) { where(user: user) }
  scope :by_agent, ->(agent) { where(assigned_agent: agent) }
  scope :unassigned, -> { where(user_id: nil, assigned_agent_id: nil) }
  scope :closing_soon, ->(days = 30) { 
    open.where('expected_close_date <= ?', days.days.from_now) 
  }
  scope :stale, ->(days = 7) { 
    open.left_joins(:activities)
        .group(:id)
        .having('MAX(activities.created_at) < ? OR MAX(activities.created_at) IS NULL', days.days.ago)
  }
  scope :high_value, ->(threshold = 10_000) { where('value >= ?', threshold) }
  scope :ordered_by_position, -> { order(position: :asc, created_at: :desc) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_default_probability, if: :stage_changed?
  before_save :set_close_date_on_close
  after_save :update_contact_lifecycle, if: :saved_change_to_stage?
  after_create :create_stage_activity

  # Stage transition methods
  def move_to_stage!(new_stage, user: nil, agent: nil, notes: nil)
    return false unless STAGES.key?(new_stage)
    return true if stage == new_stage

    old_stage = stage
    self.stage = new_stage
    
    if save
      # Log the stage change as an activity
      activities.create!(
        entity: entity,
        contact: contact,
        user: user,
        performed_by_agent: agent,
        activity_type: 'stage_change',
        subject: "Moved from #{STAGES[old_stage][:label]} to #{STAGES[new_stage][:label]}",
        description: notes,
        status: 'completed',
        completed_at: Time.current,
        metadata: { old_stage: old_stage, new_stage: new_stage }
      )
      true
    else
      false
    end
  end

  def close_won!(user: nil, agent: nil, notes: nil)
    self.actual_close_date = Date.current
    move_to_stage!('closed_won', user: user, agent: agent, notes: notes)
  end

  def close_lost!(reason:, user: nil, agent: nil, notes: nil)
    self.lost_reason = reason
    self.actual_close_date = Date.current
    move_to_stage!('closed_lost', user: user, agent: agent, notes: notes)
  end

  def reopen!(user: nil, agent: nil, notes: nil)
    return false unless closed?
    
    self.actual_close_date = nil
    self.lost_reason = nil
    move_to_stage!('qualified', user: user, agent: agent, notes: notes || 'Opportunity reopened')
  end

  # Status checks
  def open?
    !closed?
  end

  def closed?
    stage.in?(['closed_won', 'closed_lost'])
  end

  def won?
    stage == 'closed_won'
  end

  def lost?
    stage == 'closed_lost'
  end

  def stale?(days = 7)
    return false if closed?
    last_activity = activities.order(created_at: :desc).first
    return true unless last_activity
    last_activity.created_at < days.days.ago
  end

  # Assignment methods
  def assign_to_user!(user)
    update!(user: user, assigned_agent: nil)
    activities.create!(
      entity: entity,
      contact: contact,
      user: user,
      activity_type: 'assignment',
      subject: "Assigned to #{user.full_name}",
      status: 'completed',
      completed_at: Time.current
    )
  end

  def assign_to_agent!(agent)
    update!(assigned_agent: agent, user: nil)
    activities.create!(
      entity: entity,
      contact: contact,
      performed_by_agent: agent,
      activity_type: 'assignment',
      subject: "Assigned to AI Agent: #{agent.name}",
      status: 'completed',
      completed_at: Time.current
    )
  end

  def assigned?
    user_id.present? || assigned_agent_id.present?
  end

  def assigned_to
    user || assigned_agent
  end

  def assigned_name
    if user.present?
      user.full_name
    elsif assigned_agent.present?
      "AI: #{assigned_agent.name}"
    else
      'Unassigned'
    end
  end

  # Value calculations
  def weighted_value
    return 0 unless value.present? && probability.present?
    (value * probability / 100.0).round(2)
  end

  # Stage helpers
  def stage_info
    STAGES[stage] || {}
  end

  def stage_label
    stage_info[:label] || stage.titleize
  end

  def stage_color
    stage_info[:color] || '#6B7280'
  end

  def stage_passed?(check_stage)
    return false unless STAGES[check_stage]
    current_order = stage_info[:order] || 99
    check_order = STAGES[check_stage][:order] || 99
    current_order > check_order
  end

  def stage_order
    stage_info[:order] || 99
  end

  def next_stage
    current_order = stage_order
    STAGES.find { |_, info| info[:order] == current_order + 1 }&.first
  end

  def previous_stage
    current_order = stage_order
    STAGES.find { |_, info| info[:order] == current_order - 1 }&.first
  end

  # Days tracking
  def days_in_stage
    # Find when stage was last changed
    stage_change = activities.where(activity_type: 'stage_change')
                             .where("metadata->>'new_stage' = ?", stage)
                             .order(created_at: :desc)
                             .first
    
    start_date = stage_change&.created_at || created_at
    (Time.current - start_date).to_i / 1.day
  end

  def days_open
    return nil if closed?
    (Date.current - created_at.to_date).to_i
  end

  def days_to_close
    return nil unless closed? && actual_close_date
    (actual_close_date - created_at.to_date).to_i
  end

  # Class methods for pipeline stats
  def self.pipeline_stats(entity)
    opportunities = where(entity: entity)
    
    {
      total_open: opportunities.open.count,
      total_value: opportunities.open.sum(:value) || 0,
      weighted_value: opportunities.open.sum('value * probability / 100.0') || 0,
      by_stage: STAGES.keys.each_with_object({}) do |stage, hash|
        stage_opps = opportunities.by_stage(stage)
        hash[stage] = {
          count: stage_opps.count,
          value: stage_opps.sum(:value) || 0
        }
      end,
      win_rate: calculate_win_rate(opportunities),
      avg_deal_size: opportunities.won.average(:value)&.round(2) || 0,
      avg_days_to_close: opportunities.won.average('actual_close_date - DATE(created_at)')&.round(1) || 0
    }
  end

  def self.calculate_win_rate(scope = all)
    closed = scope.closed
    return 0 if closed.count.zero?
    ((scope.won.count.to_f / closed.count) * 100).round(1)
  end

  private

  def set_default_probability
    return unless STAGES[stage]
    self.probability ||= STAGES[stage][:probability]
  end

  def set_close_date_on_close
    if stage_changed? && closed? && actual_close_date.nil?
      self.actual_close_date = Date.current
    end
  end

  def lost_reason_required_when_closed_lost
    if stage == 'closed_lost' && lost_reason.blank?
      errors.add(:lost_reason, "is required when marking as closed lost")
    end
  end

  def close_date_required_when_closed
    if closed? && actual_close_date.blank?
      self.actual_close_date = Date.current
    end
  end

  def update_contact_lifecycle
    return unless contact

    new_lifecycle = case stage
                    when 'lead', 'qualified'
                      'sql'
                    when 'proposal', 'negotiation'
                      'opportunity'
                    when 'closed_won'
                      'customer'
                    end
    
    if new_lifecycle && contact.lifecycle_stage != new_lifecycle
      contact.update(lifecycle_stage: new_lifecycle)
    end
  end

  def create_stage_activity
    activities.create!(
      entity: entity,
      contact: contact,
      user: user,
      performed_by_agent: assigned_agent,
      activity_type: 'opportunity_created',
      subject: "Opportunity created: #{name}",
      description: "New opportunity worth #{ActionController::Base.helpers.number_to_currency(value || 0)}",
      status: 'completed',
      completed_at: Time.current,
      metadata: { source: source, initial_stage: stage }
    )
  end
end
