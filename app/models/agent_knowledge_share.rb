# frozen_string_literal: true

# AgentKnowledgeShare - Records of knowledge shared between agents
#
# When an agent discovers something useful, it can share that knowledge
# with other agents who might benefit. This creates a collective
# intelligence where the whole is greater than the sum of parts.
#
# Knowledge Types:
# - discovery: A new finding or insight
# - technique: A method or approach that works well
# - pattern: A recognized pattern in data or behavior
# - tool_usage: Tips for using a specific tool effectively
# - prompt_template: An effective prompt structure
#
class AgentKnowledgeShare < ApplicationRecord
  belongs_to :entity
  belongs_to :source_agent, class_name: 'AgentPlugin'
  belongs_to :target_agent, class_name: 'AgentPlugin'

  KNOWLEDGE_TYPES = %w[discovery technique pattern tool_usage prompt_template domain_expertise].freeze
  STATUSES = %w[shared acknowledged applied rejected].freeze

  validates :title, presence: true
  validates :knowledge_type, inclusion: { in: KNOWLEDGE_TYPES }, allow_nil: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :shared, -> { where(status: 'shared') }
  scope :acknowledged, -> { where(status: 'acknowledged') }
  scope :applied, -> { where(status: 'applied') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :by_type, ->(type) { where(knowledge_type: type) }
  scope :from_agent, ->(agent) { where(source_agent: agent) }
  scope :to_agent, ->(agent) { where(target_agent: agent) }
  scope :recent, -> { order(created_at: :desc) }
  scope :pending_review, -> { where(status: 'shared') }

  # ═══════════════════════════════════════════════════════════════════════════
  # STATUS TRANSITIONS
  # ═══════════════════════════════════════════════════════════════════════════

  def acknowledge!
    update!(status: 'acknowledged')
  end

  def apply!(feedback = nil)
    update!(
      status: 'applied',
      target_found_useful: true,
      target_feedback: feedback
    )
    
    # Update relationship trust
    update_relationship_after_share(positive: true)
  end

  def reject!(feedback = nil)
    update!(
      status: 'rejected',
      target_found_useful: false,
      target_feedback: feedback
    )
    
    # Don't penalize relationship for honest rejection
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def was_useful?
    target_found_useful == true
  end

  def pending?
    status == 'shared'
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  class << self
    def share_rate_for_agent(agent)
      total = from_agent(agent).count
      return 0.0 if total.zero?
      
      useful = from_agent(agent).where(target_found_useful: true).count
      (useful.to_f / total * 100).round(1)
    end

    def reception_rate_for_agent(agent)
      total = to_agent(agent).count
      return 0.0 if total.zero?
      
      applied = to_agent(agent).applied.count
      (applied.to_f / total * 100).round(1)
    end
  end

  private

  def update_relationship_after_share(positive:)
    relationship = AgentRelationship.find_or_create_between(source_agent, target_agent, entity)
    
    relationship.increment!(:knowledge_shares)
    relationship.update!(last_knowledge_share: Time.current)
    
    if positive
      new_trust = [relationship.trust_score + 0.05, 1.0].min
      relationship.update!(trust_score: new_trust)
    end
  end
end


