class AgentActivity < ApplicationRecord
  belongs_to :conversation, class_name: 'ScoutConversation'
  
  validates :agent_name, presence: true
  validates :activity_type, presence: true
  validates :processing_time_ms, presence: true, numericality: { greater_than_or_equal_to: 0 }
  
  # Agent names
  AGENT_NAMES = %w[
    conversation_engine
    intent_analyzer
    business_extractor
    context_manager
  ].freeze
  
  # Activity types
  ACTIVITY_TYPES = %w[
    message_processing
    intent_analysis
    business_extraction
    template_suggestion
    context_update
    error_handling
  ].freeze
  
  validates :agent_name, inclusion: { in: AGENT_NAMES }
  validates :activity_type, inclusion: { in: ACTIVITY_TYPES }
  
  scope :by_agent, ->(agent) { where(agent_name: agent) }
  scope :by_activity, ->(activity) { where(activity_type: activity) }
  scope :recent, -> { order(created_at: :desc) }
  scope :slow_processing, -> { where('processing_time_ms > ?', 2000) }
  
  # Performance analytics
  def self.average_processing_time(agent_name = nil)
    scope = agent_name ? by_agent(agent_name) : all
    scope.average(:processing_time_ms)
  end
  
  def self.performance_summary
    {
      total_activities: count,
      average_processing_time: average(:processing_time_ms),
      by_agent: group(:agent_name).average(:processing_time_ms),
      slow_operations: slow_processing.count
    }
  end
end
