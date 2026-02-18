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
#  model_id              :string
#  model_input_tokens    :integer          default(0)
#  model_output_tokens   :integer          default(0)
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

  has_many :agent_input_requests, dependent: :destroy
  has_many :feedbacks, class_name: 'UserFeedback', as: :feedbackable, dependent: :destroy

  # Validations
  validates :status, presence: true, inclusion: { in: %w[running completed failed waiting_for_input cancelled] }

  # Scopes
  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :waiting_for_input, -> { where(status: 'waiting_for_input') }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_agent, ->(agent_plugin) { where(agent_plugin: agent_plugin) }
  scope :for_user, ->(user) { where(user: user) }
  scope :since, ->(time) { where('created_at >= ?', time) }

  # Callbacks
  before_create :set_started_at
  after_update :bridge_to_context_graph, if: :just_completed?

  # Instance methods
  def mark_completed!(output = {})
    # Set completed_at first so we can calculate duration
    self.completed_at = Time.current

    update!(
      status: 'completed',
      output_result: output,
      completed_at: completed_at,
      duration_ms: calculate_duration
    )
    
    # If this execution was for a plan step, mark it complete and continue
    handle_plan_step_completion(output)
  end
  
  # Handle completion of a plan step execution
  def handle_plan_step_completion(output)
    return unless input_context.is_a?(Hash)
    
    plan_id = input_context['plan_id'] || input_context[:plan_id]
    step_id = input_context['step_id'] || input_context[:step_id]
    
    return unless plan_id && step_id
    
    plan = ExecutionPlan.find_by(id: plan_id)
    return unless plan
    
    Rails.logger.info "[AgentExecution] Marking plan step #{step_id} as completed"
    
    # Mark the step as completed
    plan.mark_step_completed!(step_id, result: {
      execution_id: id,
      output: output.to_s.truncate(1000),
      agent: agent_plugin.slug
    })
    
    # Continue autonomous execution if there are more steps
    if plan.status == 'executing' && plan.next_step.present?
      Rails.logger.info "[AgentExecution] Triggering next step in plan ##{plan_id}"
      PlanExecutorJob.perform_later(plan_id)
    elsif plan.all_steps_completed?
      plan.complete!
    end
  rescue => e
    Rails.logger.error "[AgentExecution] Error handling plan step completion: #{e.message}"
  end

  def mark_failed!(error_message = nil)
    output = output_result.deep_dup || {}
    output['error'] = error_message if error_message.present?
    
    # If this execution was for a plan step, mark it failed
    handle_plan_step_failure(error_message)

    # Set completed_at first so we can calculate duration
    self.completed_at = Time.current

    update!(
      status: 'failed',
      output_result: output,
      completed_at: completed_at,
      duration_ms: calculate_duration
    )
  end

  def add_tokens(count)
    increment!(:tokens_used, count)
  end

  def track_model_usage(model_id, input_tokens, output_tokens)
    update_columns(
      model_id: model_id,
      model_input_tokens: input_tokens,
      model_output_tokens: output_tokens
    )
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

  def model_display_name
    return nil unless model_id.present?

    # Extract short model name from full ARN
    # e.g., "us.anthropic.claude-sonnet-4-6-v2:0" -> "sonnet-4-6"
    model_id.split('.').last.gsub('anthropic.claude-', '').gsub('-v2:', '').gsub(':0', '')
  end

  def calculate_cost
    return 0 unless model_id.present? && model_input_tokens.to_i > 0

    # Model pricing (per 1M tokens)
    pricing = case model_id
    when /sonnet-4-6/, /sonnet-4-5/
      { input: 3.00, output: 15.00 }
    when /sonnet-3-5/
      { input: 3.00, output: 15.00 }
    when /haiku-4-5/
      { input: 1.00, output: 5.00 }
    when /haiku-3-5/
      { input: 0.80, output: 4.00 }
    when /opus-3/
      { input: 15.00, output: 75.00 }
    else
      { input: 3.00, output: 15.00 } # Default to Sonnet pricing
    end

    input_cost = (model_input_tokens / 1_000_000.0) * pricing[:input]
    output_cost = (model_output_tokens / 1_000_000.0) * pricing[:output]

    input_cost + output_cost
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

  def result_data
    output_result
  end
  
  private

  def set_started_at
    self.started_at ||= Time.current
  end

  # Handle failure of a plan step execution
  def handle_plan_step_failure(error_message)
    return unless input_context.is_a?(Hash)
    
    plan_id = input_context['plan_id'] || input_context[:plan_id]
    step_id = input_context['step_id'] || input_context[:step_id]
    
    return unless plan_id && step_id
    
    plan = ExecutionPlan.find_by(id: plan_id)
    return unless plan
    
    Rails.logger.warn "[AgentExecution] Plan step #{step_id} failed: #{error_message}"
    
    # Mark the step as failed
    plan.mark_step_failed!(step_id, error: error_message || 'Agent execution failed')
    
    # Let the PlanExecutorJob handle retry logic
    if plan.status == 'executing' && (plan.retry_count || 0) < 3
      Rails.logger.info "[AgentExecution] Scheduling retry for plan ##{plan_id}"
      PlanExecutorJob.set(wait: 5.seconds).perform_later(plan_id)
    end
  rescue => e
    Rails.logger.error "[AgentExecution] Error handling plan step failure: #{e.message}"
  end

  def calculate_duration
    return nil unless started_at && completed_at
    ((completed_at - started_at) * 1000).to_i  # Convert to milliseconds
  end

  # Check if execution just transitioned to completed or failed
  def just_completed?
    saved_change_to_status? && status.in?(%w[completed failed])
  end

  # Bridge to Context Graph for decision tracing
  def bridge_to_context_graph
    return unless defined?(IntegrationBridges::ExecutionContextBridge)
    
    # Run async to not block the execution
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        IntegrationBridges::ExecutionContextBridge.new(self).bridge!
      end
    rescue => e
      Rails.logger.debug "[AgentPluginExecution] Context bridge failed: #{e.message}"
    end
  rescue => e
    Rails.logger.debug "[AgentPluginExecution] Could not start context bridge: #{e.message}"
  end
end
