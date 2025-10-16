class AnalyticsConnection < ApplicationRecord
  belongs_to :entity
  has_many :analytics_query_logs, dependent: :destroy
  
  validates :name, presence: true
  validates :connection_type, presence: true
  validates :status, presence: true
  
  # Enums
  enum :status, {
    disconnected: 0,
    connected: 1,
    limited: 2,
    failing: 3
  }
  
  enum :connection_type, {
    postgres: 0,
    mysql: 1,
    bigquery: 2,
    snowflake: 3,
    redshift: 4,
    internal: 5  # AMOS internal database
  }
  
  # Scopes
  scope :active, -> { where(status: [:connected, :limited]) }
  
  # Default values
  after_initialize :set_defaults, if: :new_record?
  
  # Test connection
  def test_connection!
    connector = Analytics::WarehouseConnector.new(self)
    result = connector.test
    
    if result[:success]
      connected!
      update!(last_health_check: Time.current)
    else
      failing!
    end
    
    result
  rescue => e
    failing!
    { success: false, error: e.message }
  end
  
  # Get credentials (decrypt)
  def get_credentials
    return {} unless credentials.present?
    
    # Credentials are stored as JSON
    if credentials.is_a?(String)
      JSON.parse(credentials)
    else
      credentials
    end
  end
  
  private
  
  def set_defaults
    self.status ||= :disconnected
    self.credentials ||= {}
    self.metadata ||= {}
  end
end

