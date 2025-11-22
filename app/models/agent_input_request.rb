class AgentInputRequest < ApplicationRecord
  belongs_to :agent_plugin_execution

  validates :question, presence: true
  validates :status, inclusion: { in: %w[pending answered cancelled] }

  scope :pending, -> { where(status: 'pending') }
  scope :answered, -> { where(status: 'answered') }

  def answer!(content)
    update!(
      response_content: content,
      status: 'answered',
      responded_at: Time.current
    )
  end
end

