# frozen_string_literal: true

class AgentCollaborationRequest < ApplicationRecord
  belongs_to :requesting_agent, class_name: 'AgentPlugin'
  belongs_to :helper_agent, class_name: 'AgentPlugin', optional: true
  belongs_to :entity
  belongs_to :agent_plugin_execution, optional: true
  belongs_to :parent_request, class_name: 'AgentCollaborationRequest', optional: true
  has_many :child_requests, class_name: 'AgentCollaborationRequest', foreign_key: :parent_request_id
  has_many :energy_transactions, class_name: 'AgentEnergyTransaction'

  # Request types with costs
  REQUEST_TYPES = {
    'advice' => { base_cost: 2, base_reward: 5 },
    'review' => { base_cost: 2, base_reward: 5 },
    'subtask' => { base_cost: 10, base_reward: 15 },
    'full_delegation' => { base_cost: 15, base_reward: 25 }
  }.freeze

  URGENCY_LEVELS = %w[low medium high critical].freeze
  STATUSES = %w[pending accepted in_progress completed rejected expired cancelled].freeze
  MAX_DEPTH = 4

  # Validations
  validates :request_type, presence: true, inclusion: { in: REQUEST_TYPES.keys }
  validates :urgency, inclusion: { in: URGENCY_LEVELS }
  validates :status, inclusion: { in: STATUSES }
  validates :depth, numericality: { less_than_or_equal_to: MAX_DEPTH }

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :active, -> { where(status: %w[pending accepted in_progress]) }
  scope :completed, -> { where(status: 'completed') }
  scope :recent, ->(hours = 24) { where('created_at > ?', hours.hours.ago) }
  scope :by_type, ->(type) { where(request_type: type) }

  # Callbacks
  before_create :set_timeout
  before_create :calculate_depth
  before_create :set_energy_costs

  # ============================================
  # LIFECYCLE
  # ============================================

  def accept!(helper)
    return false unless pending?
    return false if expired?

    update!(
      helper_agent: helper,
      status: 'accepted',
      accepted_at: Time.current
    )
  end

  def start!
    return false unless accepted?

    update!(status: 'in_progress')
  end

  def complete!(response:, quality_rating: nil, was_helpful: nil)
    return false unless in_progress?

    update!(
      status: 'completed',
      completed_at: Time.current,
      response: response,
      quality_rating: quality_rating,
      was_helpful: was_helpful
    )

    # Reward helper
    if helper_agent.present?
      reward = calculate_helper_reward
      helper_agent.energy_state.earn!(
        reward,
        reason: 'helped_agent',
        request: self
      )
      update!(energy_reward: reward)

      # Update relationship
      relationship = AgentRelationship.find_or_create_by!(
        requester: requesting_agent,
        helper: helper_agent,
        entity: entity
      )
      relationship.record_collaboration!(
        success: was_helpful != false,
        quality: quality_rating || 0.5,
        response_time_ms: response_time_ms,
        helpfulness_rating: quality_rating
      )
    end

    true
  end

  def reject!(reason: nil)
    return false unless pending? || accepted?

    update!(
      status: 'rejected',
      feedback: reason,
      completed_at: Time.current
    )

    # Refund requester (partial)
    if energy_cost.present? && energy_cost > 0
      refund = energy_cost * 0.5
      requesting_agent.energy_state.earn!(
        refund,
        reason: 'collaboration_rejected_refund',
        request: self
      )
    end

    true
  end

  def expire!
    return false unless pending?

    update!(
      status: 'expired',
      completed_at: Time.current
    )

    # Full refund on expiry
    if energy_cost.present? && energy_cost > 0
      requesting_agent.energy_state.earn!(
        energy_cost,
        reason: 'collaboration_expired_refund',
        request: self
      )
    end

    true
  end

  # ============================================
  # STATUS CHECKS
  # ============================================

  def pending?
    status == 'pending'
  end

  def accepted?
    status == 'accepted'
  end

  def in_progress?
    status == 'in_progress'
  end

  def completed?
    status == 'completed'
  end

  def expired?
    timeout_at.present? && Time.current > timeout_at
  end

  def response_time_ms
    return nil unless completed_at && accepted_at
    ((completed_at - accepted_at) * 1000).to_i
  end

  # ============================================
  # DEPTH VALIDATION
  # ============================================

  def would_exceed_depth?
    depth >= MAX_DEPTH
  end

  def creates_cycle?
    return false unless helper_agent

    # Check if this would create A -> B -> ... -> A
    visited = Set.new([requesting_agent.id])
    current = parent_request

    while current
      return true if visited.include?(current.requesting_agent_id)
      visited << current.requesting_agent_id
      current = current.parent_request
    end

    # Also check if helper has pending request to us
    AgentCollaborationRequest.active
      .where(requesting_agent: helper_agent, helper_agent: requesting_agent)
      .exists?
  end

  private

  def set_timeout
    timeout_minutes = case urgency
                      when 'critical' then 2
                      when 'high' then 5
                      when 'medium' then 15
                      else 30
                      end

    self.timeout_at = timeout_minutes.minutes.from_now
  end

  def calculate_depth
    self.depth = parent_request ? parent_request.depth + 1 : 0
  end

  def set_energy_costs
    config = REQUEST_TYPES[request_type]
    self.energy_cost = config[:base_cost]
    self.energy_reward = config[:base_reward]
  end

  def calculate_helper_reward
    base = REQUEST_TYPES[request_type][:base_reward]

    # Bonus for quality
    if quality_rating.present? && quality_rating > 4
      base *= 1.2
    end

    # Bonus for speed
    if response_time_ms.present? && response_time_ms < 10_000
      base *= 1.1
    end

    # Penalty for unhelpful
    if was_helpful == false
      base *= 0.5
    end

    base.round(1)
  end
end

