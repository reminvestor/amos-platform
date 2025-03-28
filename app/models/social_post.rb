class SocialPost < ApplicationRecord
  belongs_to :user
  has_many :social_post_analytics, dependent: :destroy

  validates :title, presence: true
  validates :content, presence: true
  validates :platform, presence: true, inclusion: { in: %w[facebook instagram linkedin tiktok twitter] }
  validates :status, presence: true, inclusion: { in: %w[draft scheduled published failed] }
  validates :image_url, presence: true, if: :instagram?
  validates :image_url, format: { with: URI::regexp(%w[http https]), message: 'must be a valid URL' }, allow_blank: true

  scope :scheduled, -> { where(status: 'scheduled') }
  scope :published, -> { where(status: 'published') }
  scope :failed, -> { where(status: 'failed') }
  scope :draft, -> { where(status: 'draft') }
  scope :by_platform, ->(platform) { where(platform: platform) }
  scope :scheduled_for_publishing, -> { scheduled.where('scheduled_at <= ?', Time.current) }

  def latest_analytics
    social_post_analytics.order(collected_at: :desc).first
  end

  def calculate_engagement_rate
    return 0 if latest_analytics.nil?
    
    total_engagement = latest_analytics.likes + latest_analytics.comments + latest_analytics.shares
    reach = latest_analytics.reach
    return 0 if reach.zero?
    
    (total_engagement.to_f / reach) * 100
  end

  def instagram?
    platform == 'instagram'
  end

  def image?
    image_url.present?
  end
end
