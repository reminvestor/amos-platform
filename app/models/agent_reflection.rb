# frozen_string_literal: true

# AgentReflection - Agent metacognition records
#
# Stores agents' self-assessments of their performance, enabling
# continuous learning and self-improvement.
#
# Reflection Types:
# - execution: After individual task completion
# - daily: End-of-day summary
# - weekly: Weekly performance review
# - triggered: When performance issues detected
#
class AgentReflection < ApplicationRecord
  belongs_to :entity
  belongs_to :agent_plugin
  belongs_to :agent_plugin_execution, optional: true
  belongs_to :triggered_enrollment, class_name: 'AgentSchoolEnrollment', optional: true

  REFLECTION_TYPES = %w[execution daily weekly triggered].freeze

  validates :reflection_type, presence: true, inclusion: { in: REFLECTION_TYPES }
  validates :efficiency_score, numericality: { 
    only_integer: true, 
    greater_than_or_equal_to: 1, 
    less_than_or_equal_to: 10 
  }, allow_nil: true
  validates :quality_score, numericality: { 
    only_integer: true, 
    greater_than_or_equal_to: 1, 
    less_than_or_equal_to: 10 
  }, allow_nil: true

  scope :for_agent, ->(agent) { where(agent_plugin: agent) }
  scope :by_type, ->(type) { where(reflection_type: type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_issues, -> { where("jsonb_array_length(identified_issues) > 0") }
  scope :with_knowledge_gaps, -> { where("jsonb_array_length(knowledge_gaps) > 0") }
  scope :low_scores, -> { where('overall_score <= ?', 5) }
  scope :high_scores, -> { where('overall_score >= ?', 8) }

  # ═══════════════════════════════════════════════════════════════════════════
  # SCORE HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def update_overall_score!
    scores = [efficiency_score, quality_score, tool_usage_score, communication_score].compact
    return if scores.empty?
    
    update!(overall_score: (scores.sum.to_f / scores.count).round)
  end

  def score_summary
    {
      efficiency: efficiency_score,
      quality: quality_score,
      tool_usage: tool_usage_score,
      communication: communication_score,
      overall: overall_score
    }
  end

  def low_score?
    overall_score.to_i <= 5
  end

  def high_score?
    overall_score.to_i >= 8
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ISSUE HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def has_issues?
    identified_issues.present? && identified_issues.any?
  end

  def has_critical_issues?
    return false unless has_issues?
    
    identified_issues.any? { |i| i['severity'] == 'critical' || i[:severity] == 'critical' }
  end

  def critical_issues
    return [] unless has_issues?
    
    identified_issues.select { |i| i['severity'] == 'critical' || i[:severity] == 'critical' }
  end

  def actionable_issues
    return [] unless has_issues?
    
    identified_issues.select { |i| i['actionable'] == true || i[:actionable] == true }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # IMPROVEMENT HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def has_improvements?
    improvement_ideas.present? && improvement_ideas.any?
  end

  def actionable_improvements
    return [] unless has_improvements?
    
    improvement_ideas.select { |i| i['actionable'] == true || i[:actionable] == true }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # LEARNING PLAN HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def has_learning_plan?
    learning_plan.present? && learning_plan['modules'].present?
  end

  def learning_modules
    return [] unless has_learning_plan?
    learning_plan['modules'] || []
  end

  def high_priority_modules
    learning_modules.select { |m| m['priority'] == 'high' }
  end

  def mark_learning_scheduled!
    update!(learning_tasks_scheduled: true)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # KNOWLEDGE GAP HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def has_knowledge_gaps?
    knowledge_gaps.present? && knowledge_gaps.any?
  end

  def gap_topics
    return [] unless has_knowledge_gaps?
    
    knowledge_gaps.map { |g| g['topic'] || g[:topic] }.compact.uniq
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PEER COMPARISON HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def above_average?
    peer_comparison.present? && peer_comparison['relative_performance'] == 'above_average'
  end

  def below_average?
    peer_comparison.present? && peer_comparison['relative_performance'] == 'below_average'
  end

  def percentile
    peer_comparison&.dig('percentile')
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SUMMARY
  # ═══════════════════════════════════════════════════════════════════════════

  def summary
    {
      agent: agent_plugin.name,
      type: reflection_type,
      overall_score: overall_score,
      issues_count: identified_issues&.count || 0,
      has_critical: has_critical_issues?,
      improvements_count: improvement_ideas&.count || 0,
      knowledge_gaps: gap_topics,
      created_at: created_at
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  class << self
    def recent_for_agent(agent, days: 7)
      for_agent(agent)
        .where('created_at > ?', days.days.ago)
        .recent
    end

    def average_score_for_agent(agent, days: 30)
      reflections = for_agent(agent)
        .where('created_at > ?', days.days.ago)
        .where.not(overall_score: nil)
      
      return nil if reflections.empty?
      
      reflections.average(:overall_score)&.round(1)
    end

    def score_trend_for_agent(agent, days: 30)
      reflections = for_agent(agent)
        .where('created_at > ?', days.days.ago)
        .where.not(overall_score: nil)
        .order(:created_at)
      
      return 'unknown' if reflections.count < 5
      
      scores = reflections.pluck(:overall_score)
      first_half_avg = scores.first(scores.count / 2).sum.to_f / (scores.count / 2)
      second_half_avg = scores.last(scores.count / 2).sum.to_f / (scores.count / 2)
      
      diff = second_half_avg - first_half_avg
      
      if diff > 0.5
        'improving'
      elsif diff < -0.5
        'declining'
      else
        'stable'
      end
    end

    def common_knowledge_gaps(entity, days: 30)
      reflections = where(entity: entity)
        .where('created_at > ?', days.days.ago)
        .with_knowledge_gaps
      
      all_gaps = reflections.flat_map { |r| r.gap_topics }
      all_gaps.tally.sort_by { |_, count| -count }.first(10).to_h
    end

    def common_issues(entity, days: 30)
      reflections = where(entity: entity)
        .where('created_at > ?', days.days.ago)
        .with_issues
      
      all_issues = reflections.flat_map { |r| r.identified_issues.map { |i| i['type'] || i[:type] } }
      all_issues.tally.sort_by { |_, count| -count }.first(10).to_h
    end
  end
end
