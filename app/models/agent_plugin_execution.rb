# == Schema Information
#
# Table name: agent_plugin_executions
#
#  id                    :bigint           not null, primary key
#  agent_plugin_id       :bigint           not null
#  workflow_execution_id :bigint
#  user_id               :bigint           not null
#  status                :string           default("running"), not null
#  input_context         :jsonb            default({})
#  output_result         :jsonb            default({})
#  duration_ms           :integer
#  tokens_used           :integer          default(0)
#  started_at            :datetime
#  completed_at          :datetime
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
class AgentPluginExecution < ApplicationRecord
  # Associations
  belongs_to :agent_plugin
  belongs_to :workflow_execution, optional: true
  belongs_to :user

  # Validations
  validates :status, presence: true, inclusion: { in: %w[running completed failed] }

  # Scopes
  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_agent, ->(agent_plugin) { where(agent_plugin: agent_plugin) }
  scope :for_user, ->(user) { where(user: user) }
  scope :since, ->(time) { where('created_at >= ?', time) }

  # Callbacks
  before_create :set_started_at

  # Instance methods
  def mark_completed!(output = {})
    update!(
      status: 'completed',
      output_result: output,
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  def mark_failed!(error_message = nil)
    output = output_result.deep_dup || {}
    output['error'] = error_message if error_message.present?

    update!(
      status: 'failed',
      output_result: output,
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  def add_tokens(count)
    increment!(:tokens_used, count)
  end

  def execution_time
    return nil unless started_at && completed_at
    (completed_at - started_at).to_f
  end

  def success?
    status == 'completed'
  end

  def error_message
    output_result.dig('error')
  end

  # Class methods
  def self.average_duration
    completed.average(:duration_ms)&.to_i || 0
  end

  def self.success_rate
    total = count
    return 0 if total.zero?

    successful = completed.count
    ((successful.to_f / total) * 100).round(2)
  end

  def self.total_tokens_used
    sum(:tokens_used)
  end

  private

  def set_started_at
    self.started_at ||= Time.current
  end

  def calculate_duration
    return nil unless started_at && completed_at
    ((completed_at - started_at) * 1000).to_i  # Convert to milliseconds
  end
end
