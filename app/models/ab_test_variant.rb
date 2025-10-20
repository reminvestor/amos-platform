class AbTestVariant < ApplicationRecord
  belongs_to :ab_test

  validates :name, presence: true
  validates :traffic_percentage, numericality: {
    greater_than: 0,
    less_than_or_equal_to: 100
  }

  # Record an impression (someone saw this variant)
  def record_impression!
    increment!(:impressions)
    update_conversion_rate!
  end

  # Record a conversion (someone completed the goal)
  def record_conversion!
    increment!(:conversions)
    update_conversion_rate!
  end

  # Reset all metrics (when starting a test)
  def reset_metrics!
    update!(
      impressions: 0,
      conversions: 0,
      conversion_rate: 0.0,
      is_winner: false
    )
  end

  # Get uplift compared to control variant
  def uplift_vs_control
    control = ab_test.variants.find_by(is_control: true)
    return nil unless control
    return 0 if control.id == id

    return nil if control.conversion_rate.zero?

    ((conversion_rate - control.conversion_rate) / control.conversion_rate * 100).round(2)
  end

  # Statistical confidence of this variant's performance
  def confidence_score
    return 0 if impressions < 30 # Minimum sample size for confidence

    # Simple confidence based on sample size and conversion rate variance
    # More sophisticated: use z-score or Bayesian methods
    sample_confidence = [impressions / 100.0, 1.0].min
    consistency = impressions > 0 ? (1 - (conversion_rate * 0.1).abs) : 0

    (sample_confidence * consistency * 100).round(2)
  end

  private

  def update_conversion_rate!
    return if impressions.zero?

    new_rate = (conversions.to_f / impressions * 100).round(4)
    update_column(:conversion_rate, new_rate)
  end
end
