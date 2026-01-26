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
  
  # NOTE: update_agent_reputation is deprecated with Amos + Loadouts architecture
  # Agent energy/reputation was for multi-agent competition - no longer applicable
  # User feedback now flows to TaskExperience utility scores via update_experience_learning
  # after_create :update_agent_reputation  # DEPRECATED - see loadout_rl_retooling.md
  
  after_create :update_experience_learning
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

  # ============================================
  # DEPRECATED: Agent Reputation (Multi-Agent Era)
  # ============================================
  # This method is deprecated with the Amos + Loadouts architecture.
  # User feedback now flows to TaskExperience utility scores via 
  # update_experience_learning, which is the correct approach for
  # improving Amos's continual learning.
  #
  # See: docs/architecture/loadout_rl_retooling.md
  # See: docs/architecture/EXPERIENCE_LEARNING_SYSTEM.md
  #
  # def update_agent_reputation
  #   agent = associated_agent
  #   return unless agent&.energy_state
  #
  #   case rating
  #   when 1 # Thumbs up - reward the agent
  #     agent.energy_state.earn!(2.0, reason: "user_positive_feedback", ...)
  #   when -1 # Thumbs down - penalize the agent
  #     agent.energy_state.penalize!(3.0, reason: "user_negative_feedback", ...)
  #   end
  # end

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

  # ============================================
  # EXPERIENCE LEARNING INTEGRATION
  # Training-Free GRPO: User feedback closes the loop
  # ============================================
  
  # Update TaskExperience utility scores based on user feedback
  # This is the critical connection between user signals and experience learning
  def update_experience_learning
    return unless entity.present?
    return if neutral? # Only learn from clear positive/negative signals
    
    success = positive?
    
    # 1. Update any DecisionTrace associated with this execution
    update_decision_trace_outcome(success)
    
    # 2. Update TaskExperience utility scores for experiences applied during this execution
    update_experience_utility_scores(success)
    
  rescue => e
    Rails.logger.error "[ExperienceLearning] Failed to update from feedback: #{e.message}"
  end

  # Find and update the DecisionTrace outcome
  def update_decision_trace_outcome(success)
    return unless defined?(DecisionTrace)
    
    # Find decision traces related to this feedbackable
    traces = find_related_decision_traces
    return if traces.empty?
    
    outcome = success ? 'success' : 'failure'
    quality_score = success ? 0.8 : 0.3
    
    traces.each do |trace|
      # Only update if not already set (don't overwrite automated outcomes)
      next if trace.outcome.present?
      
      trace.update!(
        outcome: outcome,
        outcome_quality_score: quality_score,
        outcome_recorded_at: Time.current,
        outcome_details: {
          source: 'user_feedback',
          feedback_id: id,
          rating: rating,
          comment: comment.presence
        }
      )
      
      Rails.logger.info "[ExperienceLearning] Updated DecisionTrace #{trace.id} with " \
                        "outcome=#{outcome} from feedback #{id}"
    end
  end

  # Update utility scores for experiences that were applied during this execution
  def update_experience_utility_scores(success)
    return unless defined?(TaskExperience)
    
    # Get task type from metadata or feedbackable
    task_type = extract_task_type
    return unless task_type.present?
    
    # Get experiences that were recently applied for this task type
    # We look at experiences applied in the last hour to catch ones used for this execution
    applied_experiences = TaskExperience.where(entity: entity, task_type: task_type)
                                        .active
                                        .where('last_applied_at > ?', 1.hour.ago)
    
    applied_experiences.each do |experience|
      experience.record_outcome!(success: success)
      
      Rails.logger.info "[ExperienceLearning] Updated experience #{experience.id} utility " \
                        "(success=#{success}) from feedback #{id}"
    end
    
    # Also record this feedback as a signal for future learning
    if applied_experiences.any?
      Rails.logger.info "[ExperienceLearning] Feedback #{id} updated #{applied_experiences.count} " \
                        "experience(s) for task_type=#{task_type}"
    end
  end

  # Find decision traces related to this feedback
  def find_related_decision_traces
    return [] unless defined?(DecisionTrace)
    
    traces = []
    
    case feedbackable_type
    when "AgentPluginExecution"
      # Find traces created during this execution's timeframe
      execution = feedbackable
      if execution&.started_at && execution&.completed_at
        traces = DecisionTrace.where(entity: entity)
                              .where('created_at BETWEEN ? AND ?', 
                                     execution.started_at, 
                                     execution.completed_at + 1.minute)
      end
    when "ScoutMessage"
      # Find traces from the same session around the message time
      if session_id.present?
        message = feedbackable
        if message&.created_at
          traces = DecisionTrace.where(entity: entity)
                                .where("metadata->>'session_id' = ?", session_id)
                                .where('created_at BETWEEN ? AND ?',
                                       message.created_at - 1.minute,
                                       message.created_at + 5.minutes)
        end
      end
    when "ToolExecution"
      # Find trace for this specific tool execution
      if metadata['decision_trace_id'].present?
        trace = DecisionTrace.find_by(id: metadata['decision_trace_id'], entity: entity)
        traces = [trace] if trace
      end
    end
    
    traces.compact
  end

  # Extract task type from context
  def extract_task_type
    # Try metadata first
    return metadata['task_type'] if metadata['task_type'].present?
    
    # Try to infer from feedbackable context
    case feedbackable_type
    when "AgentPluginExecution"
      feedbackable&.input_context&.dig('task_type')
    when "ScoutMessage"
      # Could be inferred from message content
      nil
    else
      nil
    end
  end
end

