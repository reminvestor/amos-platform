class CrawlerConversation < ApplicationRecord
  belongs_to :crawler_job
  
  validates :role, presence: true, inclusion: { in: %w[user assistant system] }
  validates :content, presence: true
  validates :timestamp, presence: true
  
  before_validation :set_timestamp, on: :create
  
  private
  
  def set_timestamp
    self.timestamp ||= Time.current
  end
end
