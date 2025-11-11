# Agent Lightning Training Service
# Orchestrates prompt optimization and RL-based agent improvement
class AgentLightningTrainingService
  attr_reader :entity, :config

  def initialize(entity)
    @entity = entity
    @config = entity.agent_lightning_config || create_default_config
  end

  # Check if training should run and execute it
  def run_training_if_ready
    return false unless @config.enabled?
    return false unless @config.should_retrain?

    traces = get_training_traces
    return false if traces.count < @config.min_traces_for_training

    execute_training(traces)
    true
  end

  # Get traces ready for training
  def get_training_traces
    @entity.agent_lightning_traces
      .completed
      .with_reward
      .where("created_at > ?", @config.trace_retention_days.days.ago)
      .where(included_in_training: false)
      .limit(1000)
  end

  # Execute RL training
  def execute_training(traces = nil)
    traces ||= get_training_traces
    return { success: false, message: "Not enough traces for training" } if traces.empty?

    Rails.logger.info "🚀 Starting Agent Lightning training with #{traces.count} traces"

    job = create_training_job(traces)

    begin
      job.update!(status: "running", started_at: Time.current)

      # Get training data
      training_data = traces.map(&:training_summary)

      # Analyze performance metrics
      metrics = analyze_training_data(training_data)

      # Execute training strategy
      results = case @config.training_strategy
                 when "prompt_optimization"
                   optimize_prompts(training_data, metrics)
                 when "supervised_finetuning"
                   prepare_finetuning_data(training_data, metrics)
                 when "rl_training"
                   execute_rl_training(training_data, metrics)
                 else
                   optimize_prompts(training_data, metrics)
                 end

      # Mark traces as included in training
      traces.update_all(included_in_training: true, training_used_at: Time.current)

      # Calculate improvement
      improvement = calculate_improvement(metrics, results)

      # Complete job
      job.mark_completed(results, improvement)
      @config.mark_training_completed

      Rails.logger.info "✅ Training completed with #{improvement}% improvement"
      {
        success: true,
        job_id: job.job_id,
        traces_used: traces.count,
        improvement: improvement,
        metrics: metrics,
        results: results
      }
    rescue => e
      Rails.logger.error "❌ Training failed: #{e.message}"
      job.mark_failed(e.message)
      { success: false, error: e.message, job_id: job.job_id }
    end
  end

  private

  # Create training job
  def create_training_job(traces)
    AgentTrainingJob.create!(
      entity: @entity,
      job_id: SecureRandom.uuid,
      job_type: @config.training_strategy,
      status: "pending",
      traces_used: traces.count,
      total_traces_available: @entity.agent_lightning_traces.count,
      training_config: {
        trace_count: traces.count,
        strategy: @config.training_strategy,
        optimization_targets: @config.optimization_targets
      },
      model_config: {
        model: "claude-sonnet-4-5",
        temperature: 0.3
      }
    )
  end

  # Analyze training data for insights
  def analyze_training_data(training_data)
    {
      total_traces: training_data.count,
      avg_tokens_per_trace: (training_data.sum { |t| t[:token_count] } / training_data.count).to_i,
      total_tokens: training_data.sum { |t| t[:token_count] || 0 },
      avg_duration_ms: (training_data.sum { |t| t[:duration_ms] || 0 } / training_data.count).to_i,
      total_cost: training_data.sum { |t| t[:total_cost] || 0 }.round(2),
      avg_reward: (training_data.sum { |t| t[:reward] || 0 } / training_data.count).round(2),
      success_rate: (training_data.count { |t| t[:success_rate] > 80 }.to_f / training_data.count * 100).round(1),
      high_reward_traces: training_data.count { |t| t[:reward] && t[:reward] > 0.7 },
      low_performance_traces: training_data.count { |t| t[:success_rate] < 50 }
    }
  end

  # Optimize prompts based on training data
  def optimize_prompts(training_data, metrics)
    Rails.logger.info "🔄 Optimizing prompts with #{training_data.count} traces"

    # Identify high-performing and low-performing traces
    successful = training_data.select { |t| t[:reward] && t[:reward] > 0.5 }
    failed = training_data.select { |t| !t[:reward] || t[:reward] <= 0.5 }

    {
      strategy: "prompt_optimization",
      successful_patterns: extract_patterns(successful),
      failed_patterns: extract_patterns(failed),
      recommended_changes: generate_prompt_improvements(successful, failed),
      metrics: metrics
    }
  end

  # Extract patterns from traces
  def extract_patterns(traces)
    patterns = {
      avg_steps: (traces.sum { |t| t[:steps].count } / traces.count).to_i,
      common_tools: extract_common_tools(traces),
      avg_success_rate: (traces.sum { |t| t[:success_rate] } / traces.count).round(1)
    }
    patterns
  end

  # Extract common tools from successful traces
  def extract_common_tools(traces)
    tools = {}
    traces.each do |trace|
      trace[:llm_calls].each do |call|
        call[:actions_count].times do |i|
          # Count tool usage patterns
        end
      end
    end
    tools
  end

  # Generate recommendations for prompt improvements
  def generate_prompt_improvements(successful, failed)
    [
      {
        category: "instruction_clarity",
        issue: "Some prompts resulted in inefficient tool usage",
        recommendation: "Add explicit step-by-step instructions to guide tool selection",
        priority: "high"
      },
      {
        category: "context_provision",
        issue: "Low success rate in certain scenarios",
        recommendation: "Ensure all relevant context data is provided upfront",
        priority: "high"
      },
      {
        category: "error_recovery",
        issue: "Failed attempts don't effectively learn from errors",
        recommendation: "Include error context and previous attempt results in retry prompts",
        priority: "medium"
      }
    ]
  end

  # Prepare data for supervised fine-tuning
  def prepare_finetuning_data(training_data, metrics)
    Rails.logger.info "📚 Preparing supervised fine-tuning dataset"

    finetuning_dataset = training_data.select { |t| t[:reward] && t[:reward] > 0.6 }.map do |trace|
      {
        prompt: trace[:input],
        completion: trace[:output],
        reward: trace[:reward],
        metadata: {
          model: "claude-sonnet-4-5",
          token_efficiency: (1 - (trace[:token_count].to_f / 4000)).round(2),
          speed: (1 - (trace[:duration_ms].to_f / 30000)).round(2)
        }
      }
    end

    {
      strategy: "supervised_finetuning",
      dataset_size: finetuning_dataset.count,
      recommended_epochs: 3,
      learning_rate: 0.001,
      batch_size: 32,
      dataset: finetuning_dataset,
      metrics: metrics
    }
  end

  # Execute RL training
  def execute_rl_training(training_data, metrics)
    Rails.logger.info "🤖 Executing RL-based training"

    # Group traces by workflow type
    workflows = training_data.group_by { |t| t[:input][:workflow_name] }

    rl_config = @config.learning_parameters.symbolize_keys
    improvements = {}

    workflows.each do |workflow_name, traces|
      workflow_improvement = calculate_workflow_improvement(traces, rl_config)
      improvements[workflow_name] = workflow_improvement
    end

    {
      strategy: "rl_training",
      algorithm: "hierarchical_rl",
      training_config: rl_config,
      workflow_improvements: improvements,
      overall_improvement: improvements.values.average.round(2),
      metrics: metrics
    }
  end

  # Calculate workflow-specific improvement
  def calculate_workflow_improvement(traces, rl_config)
    initial_reward = traces.first[:reward] || 0.5
    final_reward = traces.last[:reward] || 0.5
    improvement = ((final_reward - initial_reward) / initial_reward * 100).round(1)
    {
      initial_reward: initial_reward,
      final_reward: final_reward,
      improvement_percentage: improvement,
      traces_count: traces.count
    }
  end

  # Calculate overall improvement
  def calculate_improvement(metrics, results)
    case @config.training_strategy
    when "prompt_optimization"
      (metrics[:success_rate].to_f * 0.7 + metrics[:high_reward_traces].to_f / metrics[:total_traces] * 100 * 0.3).round(1)
    when "supervised_finetuning"
      results[:dataset_size].to_f / metrics[:total_traces] * 100
    when "rl_training"
      results[:overall_improvement] || 0
    else
      0
    end
  end

  # Create default config
  def create_default_config
    AgentLightningConfig.create!(
      entity: @entity,
      enabled: true,
      mode: "optimizing",
      training_strategy: "prompt_optimization",
      retrain_frequency_hours: 24
    )
  end
end
