# frozen_string_literal: true

# PlatformPerception - Snapshot of platform health and awareness
#
# Periodic perceptions capture the state of the platform, including:
# - Health metrics for all agents
# - Anomaly detection
# - Opportunity identification
# - Threat detection
#
# These perceptions drive autonomous actions and goal generation.
#
class PlatformPerception < ApplicationRecord
  belongs_to :entity, optional: true  # null = global perception
  
  has_many :platform_anomalies, dependent: :destroy

  PERCEPTION_TYPES = %w[routine triggered deep_scan].freeze

  validates :perceived_at, presence: true
  validates :perception_type, presence: true, inclusion: { in: PERCEPTION_TYPES }
  validates :overall_health_score, numericality: { 
    greater_than_or_equal_to: 0, 
    less_than_or_equal_to: 1 
  }, allow_nil: true

  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :global, -> { where(entity_id: nil) }
  scope :by_type, ->(type) { where(perception_type: type) }
  scope :recent, -> { order(perceived_at: :desc) }
  scope :with_anomalies, -> { where('anomaly_count > 0') }
  scope :critical, -> { where('critical_anomalies > 0') }

  # ═══════════════════════════════════════════════════════════════════════════
  # HEALTH ASSESSMENT
  # ═══════════════════════════════════════════════════════════════════════════

  def healthy?
    overall_health_score.to_f >= 0.7
  end

  def needs_attention?
    overall_health_score.to_f < 0.5 || critical_anomalies > 0
  end

  def health_status
    score = overall_health_score.to_f
    case
    when score >= 0.9 then 'excellent'
    when score >= 0.7 then 'good'
    when score >= 0.5 then 'fair'
    when score >= 0.3 then 'poor'
    else 'critical'
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ANOMALY HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def has_anomalies?
    anomaly_count > 0
  end

  def has_critical_anomalies?
    critical_anomalies > 0
  end

  def critical_anomalies_list
    anomalies.select { |a| a['severity'] == 'critical' }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # OPPORTUNITY HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def has_opportunities?
    opportunities.any?
  end

  def high_value_opportunities
    opportunities.select { |o| o['value'].to_f >= 0.7 }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # THREAT HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def has_threats?
    threats.any?
  end

  def immediate_threats
    threats.select { |t| t['urgency'] == 'immediate' }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ACTIONS
  # ═══════════════════════════════════════════════════════════════════════════

  def record_action(action_details)
    self.autonomous_actions_triggered = autonomous_actions_triggered + [action_details]
    self.actions_count = autonomous_actions_triggered.count
    save!
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SUMMARY
  # ═══════════════════════════════════════════════════════════════════════════

  def summary
    {
      perceived_at: perceived_at,
      perception_type: perception_type,
      health_status: health_status,
      overall_health_score: overall_health_score,
      active_agents: active_agents,
      success_rate_24h: success_rate_24h,
      anomalies: anomaly_count,
      critical_anomalies: critical_anomalies,
      opportunities: opportunities.count,
      threats: threats.count,
      actions_triggered: actions_count
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # COMPARISON
  # ═══════════════════════════════════════════════════════════════════════════

  def compare_to_previous
    previous = self.class.where(entity: entity)
      .where('perceived_at < ?', perceived_at)
      .order(perceived_at: :desc)
      .first
    
    return nil unless previous
    
    {
      health_change: (overall_health_score.to_f - previous.overall_health_score.to_f).round(4),
      success_rate_change: (success_rate_24h.to_f - previous.success_rate_24h.to_f).round(4),
      anomaly_change: anomaly_count - previous.anomaly_count,
      improving: overall_health_score.to_f > previous.overall_health_score.to_f
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  class << self
    def latest_for_entity(entity)
      for_entity(entity).recent.first
    end

    def latest_global
      global.recent.first
    end

    def health_trend(entity, days: 7)
      perceptions = for_entity(entity)
        .where('perceived_at > ?', days.days.ago)
        .order(:perceived_at)
      
      return 'unknown' if perceptions.count < 3
      
      scores = perceptions.pluck(:overall_health_score).compact
      return 'unknown' if scores.count < 3
      
      first_half_avg = scores.first(scores.count / 2).sum / (scores.count / 2).to_f
      second_half_avg = scores.last(scores.count / 2).sum / (scores.count / 2).to_f
      
      diff = second_half_avg - first_half_avg
      
      if diff > 0.05
        'improving'
      elsif diff < -0.05
        'declining'
      else
        'stable'
      end
    end
  end
end


