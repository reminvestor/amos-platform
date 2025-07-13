class BusinessInsight < ApplicationRecord
  belongs_to :entity
  belongs_to :source_conversation, class_name: 'ScoutConversation'
  
  validates :insight_type, presence: true
  validates :content, presence: true
  validates :confidence_score, presence: true, 
            numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }
  
  # Insight types
  INSIGHT_TYPES = %w[
    company_info
    target_audience
    marketing_challenges
    industry_details
    contact_preferences
    tool_usage_patterns
    business_goals
    pain_points
  ].freeze
  
  validates :insight_type, inclusion: { in: INSIGHT_TYPES }
  
  scope :by_type, ->(type) { where(insight_type: type) }
  scope :high_confidence, -> { where('confidence_score >= ?', 0.7) }
  scope :recent, -> { order(created_at: :desc) }
  
  # Get insights for business profile updates
  def self.for_business_profile(entity_id)
    where(entity_id: entity_id)
      .high_confidence
      .group(:insight_type)
      .having('created_at = MAX(created_at)')
  end
end
