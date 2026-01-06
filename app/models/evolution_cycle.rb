# frozen_string_literal: true

# EvolutionCycle - A complete evolution iteration
#
# Records the full cycle of platform evolution:
# 1. Perception - Gathering metrics and detecting anomalies
# 2. Analysis - Understanding what's working and what's not
# 3. Hypothesis - Generating improvement ideas
# 4. Experimentation - Running A/B tests
# 5. Integration - Promoting successful changes
# 6. Documentation - Recording learnings
#
class EvolutionCycle < ApplicationRecord
  belongs_to :entity

  has_many :agent_ab_tests, dependent: :nullify
  has_many :agent_school_enrollments, dependent: :nullify
  has_many :agent_goals, through: :agent_ab_tests

  CYCLE_TYPES = %w[daily weekly monthly triggered].freeze
  STATUSES = %w[running completed failed].freeze

  validates :cycle_type, presence: true, inclusion: { in: CYCLE_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :by_type, ->(type) { where(cycle_type: type) }
  scope :recent, -> { order(started_at: :desc) }

  # ═══════════════════════════════════════════════════════════════════════════
  # LIFECYCLE
  # ═══════════════════════════════════════════════════════════════════════════

  def complete!
    update!(
      status: 'completed',
      completed_at: Time.current
    )
  end

  def fail!(error_message)
    update!(
      status: 'failed',
      completed_at: Time.current,
      analysis_results: analysis_results.merge(error: error_message)
    )
  end

  def running?
    status == 'running'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def duration_minutes
    return nil unless started_at
    end_time = completed_at || Time.current
    ((end_time - started_at) / 60).round
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE RECORDING
  # ═══════════════════════════════════════════════════════════════════════════

  def record_perception(metrics:, anomalies:, opportunities:, threats:)
    update!(
      metrics_snapshot: metrics,
      anomalies_detected: anomalies,
      opportunities_detected: opportunities,
      threats_detected: threats
    )
  end

  def record_analysis(results:, hypotheses:)
    update!(
      analysis_results: results,
      improvement_hypotheses: hypotheses
    )
  end

  def start_experiment(experiment)
    self.experiments_started = (experiments_started || 0) + 1
    save!
  end

  def record_experiment_completion(experiment, successful:)
    self.experiments_completed = (experiments_completed || 0) + 1
    self.experiments_successful = (experiments_successful || 0) + 1 if successful
    save!
  end

  def record_promotion(promotion_details)
    self.evolutions_promoted = (evolutions_promoted || []) + [promotion_details]
    save!
  end

  def record_learning(learning)
    self.learnings = (learnings || []) + [learning]
    save!
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # METRICS
  # ═══════════════════════════════════════════════════════════════════════════

  def anomaly_count
    anomalies_detected&.count || 0
  end

  def critical_anomalies
    return 0 unless anomalies_detected.present?
    anomalies_detected.count { |a| a['severity'] == 'critical' }
  end

  def opportunity_count
    opportunities_detected&.count || 0
  end

  def threat_count
    threats_detected&.count || 0
  end

  def hypothesis_count
    improvement_hypotheses&.count || 0
  end

  def promotion_count
    evolutions_promoted&.count || 0
  end

  def learning_count
    learnings&.count || 0
  end

  def experiment_success_rate
    return nil unless experiments_completed.to_i > 0
    (experiments_successful.to_f / experiments_completed * 100).round(1)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SUMMARY
  # ═══════════════════════════════════════════════════════════════════════════

  def summary
    {
      id: id,
      cycle_type: cycle_type,
      status: status,
      started_at: started_at,
      completed_at: completed_at,
      duration_minutes: duration_minutes,
      anomalies: anomaly_count,
      opportunities: opportunity_count,
      hypotheses: hypothesis_count,
      experiments_started: experiments_started,
      experiments_completed: experiments_completed,
      experiments_successful: experiments_successful,
      promotions: promotion_count,
      learnings: learning_count,
      goals_generated: goals_generated
    }
  end

  def detailed_report
    {
      **summary,
      metrics_snapshot: metrics_snapshot,
      anomalies_detected: anomalies_detected,
      opportunities_detected: opportunities_detected,
      threats_detected: threats_detected,
      analysis_results: analysis_results,
      improvement_hypotheses: improvement_hypotheses,
      evolutions_promoted: evolutions_promoted,
      learnings: learnings
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  class << self
    def latest_for_entity(entity)
      where(entity: entity).recent.first
    end

    def latest_completed(entity)
      where(entity: entity).completed.recent.first
    end

    def cycles_in_period(entity, start_date, end_date)
      where(entity: entity)
        .where(started_at: start_date..end_date)
        .order(:started_at)
    end

    def total_promotions(entity, days: 30)
      where(entity: entity)
        .where('started_at > ?', days.days.ago)
        .sum { |c| c.promotion_count }
    end

    def average_experiment_success_rate(entity, days: 30)
      cycles = where(entity: entity)
        .where('started_at > ?', days.days.ago)
        .where('experiments_completed > 0')
      
      return nil if cycles.empty?
      
      total_completed = cycles.sum(&:experiments_completed)
      total_successful = cycles.sum(&:experiments_successful)
      
      (total_successful.to_f / total_completed * 100).round(1)
    end

    def evolution_velocity(entity, days: 30)
      # Number of successful promotions per week
      cycles = where(entity: entity)
        .where('started_at > ?', days.days.ago)
      
      total_promotions = cycles.sum(&:promotion_count)
      weeks = [days / 7.0, 1].max
      
      (total_promotions / weeks).round(2)
    end
  end
end
