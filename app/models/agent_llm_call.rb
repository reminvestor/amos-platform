class AgentLlmCall < ApplicationRecord
  belongs_to :entity
  has_many :agent_tool_executions

  validates :call_id, presence: true, uniqueness: true
  validates :model, presence: true
  validates :agent_role, presence: true, inclusion: { in: %w[planner executor validator analyzer] }
  validates :status, presence: true, inclusion: { in: %w[success error throttled] }

  scope :successful, -> { where(status: "success") }
  scope :by_role, ->(role) { where(agent_role: role) }
  scope :recent, -> { order(called_at: :desc) }

  # Calculate cost per token
  def cost_per_token
    return 0 if total_tokens.zero?
    cost / total_tokens
  end

  # Was this call successful
  def successful?
    status == "success"
  end

  # Get execution summary for training
  def execution_summary
    {
      call_id: call_id,
      model: model,
      role: agent_role,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      latency_ms: latency_ms,
      status: status,
      actions_count: parsed_actions&.length || 0,
      success_score: success_score,
      cost: cost,
      timestamp: called_at.to_i
    }
  end
end
