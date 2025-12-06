# frozen_string_literal: true

# == Schema Information
#
# Table name: user_feedbacks
#
#  id                :bigint           not null, primary key
#  user_id           :bigint           not null
#  entity_id         :bigint           not null
#  feedbackable_type :string           not null
#  feedbackable_id   :bigint           not null
#  rating            :integer          not null  (-1, 0, 1)
#  comment           :text
#  feedback_type     :string           (accuracy, helpfulness, speed, overall)
#  session_id        :string
#  metadata          :jsonb
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
class UserFeedback < ApplicationRecord
  # ============================================
  # ASSOCIATIONS
  # ============================================
  
  belongs_to :user
  belongs_to :entity
  belongs_to :feedbackable, polymorphic: true

  # ============================================
  # VALIDATIONS
  # ============================================
  
  VALID_RATINGS = [ -1, 0, 1 ].freeze
  VALID_FEEDBACKABLE_TYPES = %w[
    AgentPluginExecution
    ScheduledTaskRun
    ScoutMessage
    WorkflowExecution
    ToolExecution
  ].freeze
  VALID_FEEDBACK_TYPES = %w[accuracy helpfulness speed overall].freeze

  validates :rating, presence: true, inclusion: { in: VALID_RATINGS }
  validates :feedbackable_type, presence: true, inclusion: { 
    in: VALID_FEEDBACKABLE_TYPES,
    message: "must be one of: #{VALID_FEEDBACKABLE_TYPES.join(', ')}"
  }
  validates :feedback_type, inclusion: { in: VALID_FEEDBACK_TYPES }, allow_nil: true
  validates :comment, length: { maximum: 2000 }, allow_blank: true

  # ============================================
  # SCOPES
  # ============================================
  
  scope :positive, -> { where(rating: 1) }
  scope :negative, -> { where(rating: -1) }
  scope :neutral, -> { where(rating: 0) }
  scope :with_comments, -> { where.not(comment: [ nil, "" ]) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_session, ->(session_id) { where(session_id: session_id) }
  scope :by_feedback_type, ->(type) { where(feedback_type: type) }

  # Get feedback for a specific agent (across all its executions)
  scope :for_agent, ->(agent_id) {
    where(feedbackable_type: "AgentPluginExecution")
      .joins("INNER JOIN agent_plugin_executions ON user_feedbacks.feedbackable_id = agent_plugin_executions.id")
      .where(agent_plugin_executions: { agent_plugin_id: agent_id })
  }

  # Get feedback for a specific tool (requires tool_name in metadata)
  scope :for_tool, ->(tool_name) {
    where("metadata->>'tool_name' = ?", tool_name)
  }

  # ============================================
  # CALLBACKS
  # ============================================
  
  after_create :update_agent_reputation
  after_create :broadcast_feedback_received

  # ============================================
  # CLASS METHODS
  # ============================================
  
  # Calculate satisfaction score for a set of feedbacks
  def self.satisfaction_score
    total = count
    return 0.5 if total < 5 # Not enough data

    positive_count = positive.count
    negative_count = negative.count
    rated_count = positive_count + negative_count

    return 0.5 if rated_count.zero?

    (positive_count.to_f / rated_count).clamp(0, 1)
  end

  # Aggregate feedback stats
  def self.stats
    {
      total: count,
      positive: positive.count,
      negative: negative.count,
      neutral: neutral.count,
      with_comments: with_comments.count,
      satisfaction_score: satisfaction_score
    }
  end

  # ============================================
  # INSTANCE METHODS
  # ============================================
  
  def positive?
    rating == 1
  end

  def negative?
    rating == -1
  end

  def neutral?
    rating == 0
  end

  def rating_emoji
    case rating
    when 1 then "👍"
    when -1 then "👎"
    else "😐"
    end
  end

  def rating_label
    case rating
    when 1 then "Helpful"
    when -1 then "Not helpful"
    else "Neutral"
    end
  end

  # Get the agent associated with this feedback (if applicable)
  def associated_agent
    case feedbackable_type
    when "AgentPluginExecution"
      feedbackable&.agent_plugin
    when "ScheduledTaskRun"
      feedbackable&.agent_plugin
    else
      nil
    end
  end

  private

  # Update the agent's reputation based on feedback
  def update_agent_reputation
    agent = associated_agent
    return unless agent&.energy_state

    case rating
    when 1 # Thumbs up - reward the agent
      agent.energy_state.earn!(
        2.0,
        reason: "user_positive_feedback",
        metadata: { feedback_id: id, user_id: user_id }
      )
      Rails.logger.info "👍 Agent #{agent.name} received positive feedback (#{id})"
    when -1 # Thumbs down - penalize the agent
      agent.energy_state.penalize!(
        3.0,
        reason: "user_negative_feedback",
        metadata: { feedback_id: id, user_id: user_id }
      )
      Rails.logger.info "👎 Agent #{agent.name} received negative feedback (#{id})"
    end
  rescue => e
    Rails.logger.error "Failed to update agent reputation: #{e.message}"
  end

  # Broadcast feedback for real-time updates
  def broadcast_feedback_received
    return unless session_id.present?

    ScoutChannel.broadcast_to(session_id, {
      type: "feedback_received",
      feedback_id: id,
      rating: rating,
      feedbackable_type: feedbackable_type,
      feedbackable_id: feedbackable_id
    })
  rescue => e
    Rails.logger.error "Failed to broadcast feedback: #{e.message}"
  end
end

