class AbTest < ApplicationRecord
  belongs_to :entity
  belongs_to :testable, polymorphic: true
  has_many :variants, class_name: 'AbTestVariant', dependent: :destroy

  # Status: draft, running, paused, completed, stopped
  validates :name, presence: true
  validates :status, inclusion: { in: %w[draft running paused completed stopped] }
  validates :confidence_level, numericality: { greater_than: 0, less_than: 1 }
  validates :minimum_sample_size, numericality: { greater_than: 0 }
  validate :must_have_at_least_two_variants, if: :running?
  validate :traffic_percentages_must_sum_to_100, if: :running?

  scope :active, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }

  # Start the A/B test
  def start!
    return false unless can_start?

    transaction do
      update!(status: 'running', started_at: Time.current)
      variants.each(&:reset_metrics!)
    end

    true
  end

  # Pause the test
  def pause!
    update!(status: 'paused')
  end

  # Resume paused test
  def resume!
    return false unless paused?
    update!(status: 'running')
  end

  # Stop the test (cannot be restarted)
  def stop!
    update!(status: 'stopped', ended_at: Time.current)
  end

  # Complete the test and select winner
  def complete!(force: false)
    unless force
      return false unless has_sufficient_data?
    end

    winner = calculate_winner

    transaction do
      if winner
        results_data = {
          winner_id: winner.id,
          winner_name: winner.name,
          statistical_significance: true,
          confidence_level: confidence_level,
          completed_at: Time.current,
          variants: variants.map do |v|
            {
              id: v.id,
              name: v.name,
              impressions: v.impressions,
              conversions: v.conversions,
              conversion_rate: v.conversion_rate,
              is_winner: v.id == winner.id
            }
          end
        }

        winner.update!(is_winner: true)
        update!(
          status: 'completed',
          ended_at: Time.current,
          results: results_data
        )
      else
        # No statistical significance yet
        results_data = {
          statistical_significance: false,
          message: 'No statistically significant winner found',
          minimum_sample_size: minimum_sample_size,
          current_sample_size: total_impressions,
          variants: variants.map do |v|
            {
              id: v.id,
              name: v.name,
              impressions: v.impressions,
              conversions: v.conversions,
              conversion_rate: v.conversion_rate
            }
          end
        }

        update!(results: results_data) unless force
        return false
      end
    end

    true
  end

  # Calculate the winning variant using statistical analysis
  def calculate_winner
    return nil unless has_sufficient_data?

    # Use Chi-square test for statistical significance
    chi_square_service = AbTesting::ChiSquareTest.new(variants)

    if chi_square_service.significant?(confidence_level)
      # Return variant with highest conversion rate
      variants.max_by(&:conversion_rate)
    else
      nil
    end
  end

  # Check if test has sufficient data for analysis
  def has_sufficient_data?
    total_impressions >= minimum_sample_size &&
      variants.all? { |v| v.impressions >= (minimum_sample_size / variants.count) }
  end

  # Total impressions across all variants
  def total_impressions
    variants.sum(:impressions)
  end

  # Total conversions across all variants
  def total_conversions
    variants.sum(:conversions)
  end

  # Overall conversion rate
  def overall_conversion_rate
    return 0 if total_impressions.zero?
    (total_conversions.to_f / total_impressions * 100).round(2)
  end

  # Progress towards minimum sample size
  def progress_percentage
    return 100 if total_impressions >= minimum_sample_size
    (total_impressions.to_f / minimum_sample_size * 100).round(2)
  end

  # Current leader (highest conversion rate)
  def current_leader
    variants.max_by(&:conversion_rate)
  end

  # Days running
  def days_running
    return 0 unless started_at
    end_time = ended_at || Time.current
    ((end_time - started_at) / 1.day).round
  end

  private

  def can_start?
    draft? && variants.count >= 2
  end

  def must_have_at_least_two_variants
    if variants.count < 2
      errors.add(:variants, 'must have at least 2 variants')
    end
  end

  def traffic_percentages_must_sum_to_100
    total = variants.sum(&:traffic_percentage)
    unless (total - 100.0).abs < 0.01 # Allow for floating point precision
      errors.add(:variants, "traffic percentages must sum to 100% (currently #{total}%)")
    end
  end

  def draft?
    status == 'draft'
  end

  def running?
    status == 'running'
  end

  def paused?
    status == 'paused'
  end
end
