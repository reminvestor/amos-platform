class AgentLightningTrace < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :workflow_execution, optional: true
  belongs_to :task_session, optional: true

  has_many :agent_llm_calls, dependent: :destroy
  has_many :agent_tool_executions, dependent: :destroy
  has_many :agent_phase_executions, dependent: :destroy
  has_many :agent_rewards, dependent: :destroy

  validates :trace_id, presence: true, uniqueness: true
  validates :trace_type, presence: true, inclusion: { in: %w[workflow llm_call tool_execution phase_execution benchmark agent_execution] }
  validates :status, presence: true, inclusion: { in: %w[pending running completed failed training_ready] }

  scope :for_training, -> { where(included_in_training: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: %w[completed failed]) }
  scope :with_reward, -> { where.not(reward_signal: nil) }

  # Calculate total cost for this trace
  def total_cost
    cost_estimate || agent_llm_calls.sum(:cost).to_d
  end

  # Get all rewards for this trace
  def total_reward
    agent_rewards.sum(:reward_value).to_d
  end

  # Mark trace as ready for training
  def mark_training_ready
    update!(status: "training_ready", included_in_training: true)
  end

  # Calculate success rate based on intermediate steps
  def success_rate
    return 0 if intermediate_steps.empty?
    successful_steps = intermediate_steps.count { |step| step["status"] == "success" }
    (successful_steps.to_f / intermediate_steps.length * 100).round(2)
  end

  # Get trace summary for training data
  def training_summary
    {
      trace_id: trace_id,
      type: trace_type,
      input: input_data,
      output: output_data,
      steps: intermediate_steps,
      token_count: token_count,
      duration_ms: duration_ms,
      reward: reward_signal,
      success_rate: success_rate,
      timestamp: created_at.to_i
    }
  end
end
