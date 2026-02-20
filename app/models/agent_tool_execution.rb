class AgentToolExecution < ApplicationRecord
  belongs_to :entity
  belongs_to :agent_llm_call, optional: true
  belongs_to :parent, class_name: "AgentToolExecution", optional: true
  has_many :children, class_name: "AgentToolExecution", foreign_key: :parent_tool_execution_id

  validates :execution_id, presence: true, uniqueness: true
  validates :tool_name, presence: true
  validates :tool_category, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending running success error] }

  scope :successful, -> { where(status: "success") }
  scope :by_tool, ->(tool_name) { where(tool_name: tool_name) }
  scope :recent, -> { order(started_at: :desc) }

  # Was execution successful
  def successful?
    status == "success"
  end

  # Check if tool met expectations
  def quality_assessed?
    !result_met_expectations.nil?
  end

  # Get tool execution summary for training
  def execution_summary
    {
      execution_id: execution_id,
      tool: tool_name,
      category: tool_category,
      status: status,
      duration_ms: execution_time_ms,
      sequence: sequence_number,
      successful: successful?,
      quality: execution_quality_score,
      timestamp: started_at&.to_i
    }
  end

  # Get execution chain (this tool and its children)
  def execution_chain
    [self] + children.flat_map(&:execution_chain)
  end
end
