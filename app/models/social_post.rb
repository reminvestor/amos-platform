class SocialPost < ApplicationRecord
  belongs_to :user
  has_many :social_post_analytics, dependent: :destroy

  validates :title, presence: true
  validates :content, presence: true
  validates :platform, presence: true, inclusion: { in: %w[facebook instagram linkedin twitter] }
  validates :status, presence: true, inclusion: { in: %w[draft scheduled published failed] }
  validates :image_url, presence: true, if: :instagram?
  validates :image_url, format: { with: URI::regexp(%w[http https]), message: 'must be a valid URL' }, allow_blank: true

  # Set default settings
  before_validation :initialize_settings, on: :create

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
  
  # Get settings hash
  def settings_data
    read_attribute(:settings) || {}
  end
  
  # Update a section of settings
  def update_settings(section, data)
    current_settings = settings_data
    
    # Create or update the section
    if current_settings[section].present?
      current_settings[section].merge!(data)
    else
      current_settings[section] = data
    end
    
    # Save the updated settings
    update_column(:settings, current_settings)
  end
  
  # Get posts data
  def posts_data
    settings_data['posts'] || {}
  end
  
  # Check if the post has been posted to a platform
  def posted_to?(platform_id)
    posts_data.has_key?(platform_id) && posts_data[platform_id]['success']
  end
  
  private
  
  def initialize_settings
    self.settings ||= {}
  end
end
