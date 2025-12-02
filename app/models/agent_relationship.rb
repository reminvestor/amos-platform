# frozen_string_literal: true

class AgentRelationship < ApplicationRecord
  belongs_to :requester, class_name: 'AgentPlugin'
  belongs_to :helper, class_name: 'AgentPlugin'
  belongs_to :entity
  belongs_to :inherited_from, class_name: 'AgentRelationship', optional: true

  # Validations
  validates :requester_id, uniqueness: { scope: :helper_id }
  validate :different_agents

  # Scopes
  scope :strong, -> { where('compatibility_score > ?', 0.7) }
  scope :weak, -> { where('compatibility_score < ?', 0.3) }
  scope :active, -> { joins(:requester, :helper).merge(AgentPlugin.active) }

  # ============================================
  # COLLABORATION TRACKING
  # ============================================

  def record_collaboration!(outcome)
    self.total_collaborations += 1
    self.successful_collaborations += 1 if outcome[:success]
    self.total_quality += outcome[:quality] || 0.5
    self.total_response_time_ms += outcome[:response_time_ms] || 0

    if outcome[:helpfulness_rating].present?
      self.helpfulness_ratings << outcome[:helpfulness_rating]
    end

    recalculate_scores!
    save!
  end

  def recalculate_scores!
    self.compatibility_score = calculate_compatibility
    self.trust_score = calculate_trust
  end

  # ============================================
  # COMPUTED METRICS
  # ============================================

  def success_rate
    return 0.5 if total_collaborations.zero?
    successful_collaborations.to_f / total_collaborations
  end

  def avg_quality
    return 0.5 if total_collaborations.zero?
    total_quality / total_collaborations
  end

  def avg_response_time_ms
    return nil if total_collaborations.zero?
    total_response_time_ms / total_collaborations
  end

  def avg_helpfulness
    return 0.5 if helpfulness_ratings.empty?
    helpfulness_ratings.sum.to_f / helpfulness_ratings.size
  end

  # ============================================
  # INHERITANCE
  # ============================================

  def self.inherit_from!(old_agent, new_agent, inheritance_rate: 0.7)
    # Transfer relationships where old_agent was the requester
    old_agent.relationships_as_requester.find_each do |rel|
      create!(
        requester: new_agent,
        helper: rel.helper,
        entity: rel.entity,
        total_collaborations: (rel.total_collaborations * inheritance_rate).floor,
        successful_collaborations: (rel.successful_collaborations * inheritance_rate).floor,
        total_quality: rel.total_quality * inheritance_rate,
        total_response_time_ms: (rel.total_response_time_ms * inheritance_rate).to_i,
        helpfulness_ratings: rel.helpfulness_ratings.last(5),  # Keep recent ratings
        compatibility_score: rel.compatibility_score * inheritance_rate,
        trust_score: rel.trust_score * inheritance_rate,
        inherited_from: rel
      )
    end

    # Transfer relationships where old_agent was the helper
    old_agent.relationships_as_helper.find_each do |rel|
      create!(
        requester: rel.requester,
        helper: new_agent,
        entity: rel.entity,
        total_collaborations: (rel.total_collaborations * inheritance_rate).floor,
        successful_collaborations: (rel.successful_collaborations * inheritance_rate).floor,
        total_quality: rel.total_quality * inheritance_rate,
        total_response_time_ms: (rel.total_response_time_ms * inheritance_rate).to_i,
        helpfulness_ratings: rel.helpfulness_ratings.last(5),
        compatibility_score: rel.compatibility_score * inheritance_rate,
        trust_score: rel.trust_score * inheritance_rate,
        inherited_from: rel
      )
    end
  end

  private

  def different_agents
    if requester_id == helper_id
      errors.add(:base, "Agent cannot have a relationship with itself")
    end
  end

  def calculate_compatibility
    return 0.5 if total_collaborations < 3

    # Weighted combination of factors
    weights = {
      success_rate: 0.3,
      quality: 0.3,
      speed: 0.2,
      helpfulness: 0.2
    }

    speed_score = if avg_response_time_ms
      # Normalize response time (faster = better, assume 30s is baseline)
      [1.0 - (avg_response_time_ms / 30_000.0), 0.0].max
    else
      0.5
    end

    score = weights[:success_rate] * success_rate +
            weights[:quality] * avg_quality +
            weights[:speed] * speed_score +
            weights[:helpfulness] * (avg_helpfulness / 5.0)

    score.clamp(0.0, 1.0)
  end

  def calculate_trust
    return 0.5 if total_collaborations < 5

    # Trust builds slowly, erodes quickly
    base_trust = success_rate * 0.6 + avg_quality * 0.4

    # Boost for consistent performance
    if total_collaborations > 20 && success_rate > 0.8
      base_trust *= 1.1
    end

    # Penalty for recent failures
    recent_failures = helpfulness_ratings.last(5).count { |r| r < 3 }
    if recent_failures > 2
      base_trust *= 0.8
    end

    base_trust.clamp(0.0, 1.0)
  end
end

