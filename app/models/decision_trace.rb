# frozen_string_literal: true

# DecisionTrace - The Core of Our Context Graph
#
# This model captures the "WHY" behind every agent decision, enabling:
# 1. Precedent search ("what similar decisions were made?")
# 2. Exception tracking ("was this an exception to normal policy?")
# 3. Approval chains ("who approved this deviation?")
# 4. Learning from patterns ("what works in situations like this?")
#
# This is the foundation of our trillion-dollar context graph opportunity.
#
class DecisionTrace < ApplicationRecord
  belongs_to :entity
  belongs_to :user, optional: true
  belongs_to :agent_plugin, optional: true
  belongs_to :agent_lightning_trace, optional: true
  belongs_to :parent_decision, class_name: 'DecisionTrace', optional: true
  
  has_many :child_decisions, class_name: 'DecisionTrace', foreign_key: :parent_decision_id
  has_many :decision_precedents, dependent: :destroy
  has_many :precedents, through: :decision_precedents, source: :precedent_decision

  # Decision types
  DECISION_TYPES = %w[
    action           # Took an action (called a tool)
    delegation       # Delegated to another agent
    escalation       # Escalated to a human
    exception        # Made an exception to normal policy
    approval         # Approved something (human or agent)
    rejection        # Rejected something
    recommendation   # Made a recommendation
    synthesis        # Synthesized information from multiple sources
  ].freeze

  # Approval status
  APPROVAL_STATUSES = %w[pending approved rejected auto_approved].freeze

  validates :decision_type, inclusion: { in: DECISION_TYPES }
  validates :trace_id, presence: true, uniqueness: true
  validates :decision_summary, presence: true

  # For vector similarity search on decisions
  has_neighbors :embedding

  scope :recent, -> { order(created_at: :desc) }
  scope :exceptions, -> { where(is_exception: true) }
  scope :approved, -> { where(approval_status: 'approved') }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :by_type, ->(type) { where(decision_type: type) }
  scope :with_precedents, -> { joins(:decision_precedents).distinct }

  before_validation :generate_trace_id, on: :create
  after_create :generate_embedding
  after_update :trigger_immediate_learning, if: :outcome_changed_to_terminal?

  # ═══════════════════════════════════════════════════════════════════════════
  # CREATION HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  # Record a decision with full context
  def self.record_decision!(
    entity:,
    decision_type:,
    decision_summary:,
    reasoning:,
    context_gathered: {},
    inputs_used: [],
    policies_evaluated: [],
    agent_plugin: nil,
    user: nil,
    agent_lightning_trace: nil,
    is_exception: false,
    exception_justification: nil,
    requires_approval: false,
    approved_by: nil,
    outcome: nil,
    confidence_score: nil,
    metadata: {}
  )
    decision = create!(
      entity: entity,
      agent_plugin: agent_plugin,
      user: user,
      agent_lightning_trace: agent_lightning_trace,
      decision_type: decision_type,
      decision_summary: decision_summary,
      reasoning: reasoning,
      context_gathered: context_gathered,
      inputs_used: inputs_used,
      policies_evaluated: policies_evaluated,
      is_exception: is_exception,
      exception_justification: exception_justification,
      requires_approval: requires_approval,
      approval_status: requires_approval ? 'pending' : 'auto_approved',
      approved_by: approved_by,
      approved_at: requires_approval ? nil : Time.current,
      outcome: outcome,
      confidence_score: confidence_score,
      metadata: metadata
    )

    # Find and link similar precedents
    decision.find_and_link_precedents!

    decision
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PRECEDENT SEARCH (The Key Innovation)
  # ═══════════════════════════════════════════════════════════════════════════

  # Find similar decisions that could serve as precedent
  def find_similar_decisions(limit: 10, min_similarity: 0.7)
    return [] unless embedding.present?

    # Search by vector similarity
    similar = DecisionTrace
      .where.not(id: id)
      .where(entity: entity)
      .nearest_neighbors(:embedding, embedding, distance: :cosine)
      .limit(limit * 2)

    # Filter by similarity threshold and enrich with metadata
    similar.filter_map do |decision|
      similarity = 1.0 - decision.neighbor_distance
      next if similarity < min_similarity

      {
        decision: decision,
        similarity: similarity.round(3),
        outcome_known: decision.outcome.present?,
        was_successful: decision.was_successful?,
        days_ago: ((Time.current - decision.created_at) / 1.day).round
      }
    end.first(limit)
  end

  # Find precedents for a given context (before making a decision)
  def self.find_precedents_for(entity:, context_description:, decision_type: nil, limit: 5)
    # Generate embedding for the context
    embedding = generate_embedding_for_text(context_description)
    return [] unless embedding

    scope = where(entity: entity)
    scope = scope.where(decision_type: decision_type) if decision_type
    scope = scope.where(outcome: 'success')  # Only successful precedents

    scope
      .nearest_neighbors(:embedding, embedding, distance: :cosine)
      .limit(limit)
      .map do |decision|
        {
          decision: decision,
          similarity: (1.0 - decision.neighbor_distance).round(3),
          summary: decision.decision_summary,
          reasoning: decision.reasoning,
          outcome: decision.outcome,
          was_exception: decision.is_exception?
        }
      end
  end

  # Find exception precedents (when considering making an exception)
  def self.find_exception_precedents(entity:, context_description:, limit: 5)
    find_precedents_for(
      entity: entity,
      context_description: context_description,
      decision_type: 'exception',
      limit: limit
    ).select { |p| p[:decision].is_exception? }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # EXCEPTION HANDLING
  # ═══════════════════════════════════════════════════════════════════════════

  # Record that this was an exception with justification
  def mark_as_exception!(justification:, policy_overridden: nil)
    update!(
      is_exception: true,
      exception_justification: justification,
      policies_evaluated: (policies_evaluated || []) + [
        {
          policy: policy_overridden,
          action: 'overridden',
          justification: justification,
          timestamp: Time.current.iso8601
        }
      ]
    )
  end

  # Check if similar exceptions have been granted before
  def similar_exceptions_granted?
    return false unless is_exception?

    similar = find_similar_decisions(limit: 5, min_similarity: 0.75)
    similar.any? { |s| s[:decision].is_exception? && s[:decision].was_successful? }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # APPROVAL CHAIN
  # ═══════════════════════════════════════════════════════════════════════════

  def approve!(approved_by:, notes: nil)
    update!(
      approval_status: 'approved',
      approved_by: approved_by,
      approved_at: Time.current,
      approval_notes: notes
    )
  end

  def reject!(rejected_by:, notes: nil)
    update!(
      approval_status: 'rejected',
      approved_by: rejected_by,  # Person who rejected
      approved_at: Time.current,
      approval_notes: notes
    )
  end

  def pending_approval?
    requires_approval? && approval_status == 'pending'
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # OUTCOME TRACKING
  # ═══════════════════════════════════════════════════════════════════════════

  def record_outcome!(outcome:, outcome_details: {}, quality_score: nil)
    update!(
      outcome: outcome,
      outcome_details: outcome_details,
      outcome_quality_score: quality_score,
      outcome_recorded_at: Time.current
    )

    # Update precedent links with outcome info
    decision_precedents.each do |link|
      link.update!(
        outcome_matches: link.precedent_decision.outcome == outcome
      )
    end
  end

  def was_successful?
    outcome == 'success'
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONTEXT GRAPH QUERIES
  # ═══════════════════════════════════════════════════════════════════════════

  # Get the full decision chain (parent -> this -> children)
  def decision_chain
    chain = []
    
    # Walk up to root
    current = self
    while current.parent_decision
      chain.unshift(current.parent_decision)
      current = current.parent_decision
    end
    
    chain << self
    
    # Add children
    chain + child_decisions.order(:created_at).to_a
  end

  # Get all inputs that influenced this decision
  def all_inputs
    {
      direct_inputs: inputs_used,
      context: context_gathered,
      precedents: decision_precedents.map do |dp|
        {
          decision_id: dp.precedent_decision_id,
          summary: dp.precedent_decision.decision_summary,
          similarity: dp.similarity_score,
          influenced_by: dp.influence_type
        }
      end,
      policies: policies_evaluated
    }
  end

  # Serialize for context graph visualization
  def to_graph_node
    {
      id: id,
      trace_id: trace_id,
      type: decision_type,
      summary: decision_summary,
      is_exception: is_exception?,
      outcome: outcome,
      confidence: confidence_score,
      agent: agent_plugin&.name,
      user: user&.email,
      created_at: created_at,
      precedent_ids: decision_precedents.pluck(:precedent_decision_id),
      child_ids: child_decisions.pluck(:id)
    }
  end

  # Called after creation to find similar past decisions
  def find_and_link_precedents!
    similar = find_similar_decisions(limit: 3, min_similarity: 0.75)
    
    similar.each do |match|
      DecisionPrecedent.create!(
        decision_trace: self,
        precedent_decision: match[:decision],
        similarity_score: match[:similarity],
        influence_type: determine_influence_type(match[:decision])
      )
    end
  rescue => e
    Rails.logger.warn "Failed to link precedents: #{e.message}"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # IMMEDIATE LEARNING (Training-Free GRPO)
  # ═══════════════════════════════════════════════════════════════════════════

  # Check if outcome changed to a terminal state (success/failure)
  def outcome_changed_to_terminal?
    saved_change_to_outcome? && outcome.in?(%w[success failure])
  end

  # Trigger immediate learning when outcome is recorded
  def trigger_immediate_learning
    return unless outcome.present?

    # Run in background to avoid slowing down the request
    ImmediateLearningJob.perform_later(id)
  rescue => e
    Rails.logger.warn "[DecisionTrace] Failed to queue immediate learning: #{e.message}"
  end

  private

  def generate_trace_id
    self.trace_id ||= "dt_#{SecureRandom.uuid}"
  end

  def generate_embedding
    return unless decision_summary.present?

    text = [
      decision_summary,
      reasoning,
      context_gathered.to_json
    ].compact.join(" ")

    self.embedding = self.class.generate_embedding_for_text(text)
    save! if embedding_changed?
  rescue => e
    Rails.logger.warn "Failed to generate decision embedding: #{e.message}"
  end

  def self.generate_embedding_for_text(text)
    return nil if text.blank?

    # Use Bedrock Titan for embeddings
    service = BedrockEmbeddingService.new
    service.generate_embedding(text.truncate(8000))
  rescue => e
    Rails.logger.warn "Failed to generate embedding: #{e.message}"
    nil
  end

  def determine_influence_type(precedent)
    if precedent.is_exception? && is_exception?
      'exception_precedent'
    elsif precedent.outcome == 'success'
      'success_pattern'
    elsif precedent.outcome == 'failure'
      'failure_avoidance'
    else
      'context_similarity'
    end
  end
end

