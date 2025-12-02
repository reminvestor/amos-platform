# app/models/ocr_metric.rb
class OcrMetric < ApplicationRecord
  belongs_to :entity
  belongs_to :rag_document, optional: true

  validates :provider, presence: true
  validates :operation_type, presence: true

  # Scopes for reporting
  scope :successful, -> { where(status: 'success') }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { where('created_at >= ?', 30.days.ago) }
  scope :this_month, -> { where('created_at >= ?', Time.current.beginning_of_month) }
  scope :by_provider, ->(provider) { where(provider: provider) }

  # Calculate total costs
  def self.total_cost
    sum(:estimated_cost_usd)
  end

  # Calculate average processing time
  def self.average_processing_time
    average(:processing_time_ms)
  end

  # Get provider breakdown
  def self.provider_breakdown
    group(:provider).select(
      'provider',
      'COUNT(*) as operation_count',
      'SUM(estimated_cost_usd) as total_cost',
      'AVG(processing_time_ms) as avg_processing_time'
    )
  end
end
