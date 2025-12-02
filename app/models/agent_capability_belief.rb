# frozen_string_literal: true

class AgentCapabilityBelief < ApplicationRecord
  belongs_to :agent_plugin

  # Validations
  validates :task_type, presence: true
  validates :agent_plugin_id, uniqueness: { scope: :task_type }

  # Scopes
  scope :specialties, -> { where(is_specialty: true) }
  scope :weaknesses, -> { where(is_weakness: true) }
  scope :for_task_type, ->(type) { where(task_type: type) }

  # ============================================
  # LEARNING
  # ============================================

  def update_from_outcome!(success:, quality:)
    self.attempts += 1
    self.successes += 1 if success
    self.total_quality += quality
    self.avg_quality = total_quality / attempts

    # Update Bayesian confidence interval
    self.confidence_interval = calculate_confidence_interval

    save!
  end

  def success_rate
    return 0.5 if attempts.zero?
    successes.to_f / attempts
  end

  # ============================================
  # SPECIALIZATION DETECTION
  # ============================================

  def recalculate_specialization!(population_stats)
    return if attempts < 5  # Not enough data

    # Calculate z-score compared to population
    mean = population_stats[:mean] || 0.5
    std_dev = population_stats[:std_dev] || 0.1
    std_dev = 0.1 if std_dev < 0.01  # Prevent division by zero

    self.z_score = (avg_quality - mean) / std_dev

    # Determine specialty/weakness
    if z_score > 1.5
      self.is_specialty = true
      self.is_weakness = false
    elsif z_score < -1.0
      self.is_specialty = false
      self.is_weakness = true
    else
      self.is_specialty = false
      self.is_weakness = false
    end

    save!
  end

  # ============================================
  # CONFIDENCE ESTIMATION
  # ============================================

  def confidence_for_task
    return 50.0 if attempts < 3

    # Base confidence on success rate and quality
    base = (success_rate * 50) + (avg_quality * 50)

    # Adjust by confidence interval width (narrower = more confident)
    interval_width = confidence_interval[1] - confidence_interval[0]
    confidence_adjustment = (1 - interval_width) * 20

    (base + confidence_adjustment).clamp(0, 100)
  end

  private

  def calculate_confidence_interval
    return [0.0, 1.0] if attempts < 3

    # Wilson score interval for binomial proportion
    z = 1.96  # 95% confidence
    n = attempts.to_f
    p_hat = successes.to_f / n

    denominator = 1 + z**2 / n
    center = (p_hat + z**2 / (2 * n)) / denominator
    margin = z * Math.sqrt((p_hat * (1 - p_hat) + z**2 / (4 * n)) / n) / denominator

    [
      (center - margin).clamp(0, 1),
      (center + margin).clamp(0, 1)
    ]
  end
end

