class SocialPostAnalytic < ApplicationRecord
  belongs_to :social_post

  validates :collected_at, presence: true
  validates :likes, :comments, :shares, :views, :reach, numericality: { greater_than_or_equal_to: 0 }
  validates :engagement_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  before_save :calculate_engagement_rate

  private

  def calculate_engagement_rate
    return if reach.zero?
    
    total_engagement = likes + comments + shares
    self.engagement_rate = (total_engagement.to_f / reach) * 100
  end
end
