class MetricDefinition < ApplicationRecord
  # Versioned metric definitions for analytics queries
  
  validates :name, presence: true
  validates :version, presence: true
  validates :expression, presence: true
  validates :time_column, presence: true
  
  # Composite unique constraint
  validates :name, uniqueness: { scope: :version }
  
  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :by_category, ->(category) { where(category: category) }
  scope :latest_version, -> { 
    select('DISTINCT ON (name) *')
      .order('name, version DESC')
  }
  
  # Default values
  after_initialize :set_defaults, if: :new_record?
  
  # Get latest version of a metric
  def self.latest_for(metric_name)
    where(name: metric_name, is_active: true)
      .order(version: :desc)
      .first
  end
  
  # Get all available dimensions
  def available_dimensions
    dimensions || []
  end
  
  # Get default filters
  def default_filters
    filters_default || {}
  end
  
  # Get grain (day, week, month)
  def default_grain
    grain_default || 'week'
  end
  
  private
  
  def set_defaults
    self.is_active = true if is_active.nil?
    self.grain_default ||= 'week'
    self.dimensions ||= []
    self.filters_default ||= {}
    self.quality_rules ||= []
    self.metadata ||= {}
  end
end

