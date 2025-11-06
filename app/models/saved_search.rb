class SavedSearch < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  
  validates :name, presence: true
  validates :query_params, presence: true
  validates :alert_frequency, inclusion: { in: %w[daily weekly monthly], allow_nil: true }
  
  scope :alerts_enabled, -> { where(alert_enabled: true) }
  scope :due_for_check, -> {
    alerts_enabled.where(
      'last_run_at IS NULL OR last_run_at < ?',
      case
      when 'daily' then 1.day.ago
      when 'weekly' then 1.week.ago
      when 'monthly' then 1.month.ago
      else 1.day.ago
      end
    )
  }
  
  # Run the saved search
  def run
    DocumentSearchService.new(entity).search(
      query: query_params['query'],
      filters: query_params['filters'] || {},
      use_ai: query_params['use_ai'] || false
    )
  end
  
  # Check for new results
  def check_for_updates
    return unless alert_enabled
    
    current_results = run
    
    # Compare with last result count
    new_results = current_results[:total_count] > result_count
    
    if new_results
      send_alert(current_results)
    end
    
    # Update tracking
    update!(
      last_run_at: Time.current,
      result_count: current_results[:total_count]
    )
    
    new_results
  end
  
  # Build search URL
  def search_url
    Rails.application.routes.url_helpers.documents_url(
      q: query_params['query'],
      **query_params['filters']
    )
  end
  
  # Human readable frequency
  def frequency_text
    return 'Never' unless alert_enabled
    
    alert_frequency&.humanize || 'Not set'
  end
  
  # Next check time
  def next_check_at
    return nil unless alert_enabled && last_run_at
    
    case alert_frequency
    when 'daily'
      last_run_at + 1.day
    when 'weekly'
      last_run_at + 1.week
    when 'monthly'
      last_run_at + 1.month
    end
  end
  
  private
  
  def send_alert(results)
    SavedSearchMailer.new_results(self, results).deliver_later
    update_column(:last_alert_at, Time.current)
  end
end
