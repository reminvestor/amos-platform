class CrawlerJobLog < ApplicationRecord
  belongs_to :crawler_job
  
  # Possible log levels
  LOG_LEVELS = %w[debug info warning error]
  
  # Validation
  validates :message, presence: true
  validates :log_level, inclusion: { in: LOG_LEVELS, allow_blank: true }
  
  # Default scope to order logs by timestamp
  default_scope { order(timestamp: :asc) }
  
  # Create a log entry with the current timestamp
  def self.log(crawler_job, message, level = 'info')
    create(
      crawler_job: crawler_job,
      message: message,
      log_level: level,
      timestamp: Time.current
    )
  end
end
