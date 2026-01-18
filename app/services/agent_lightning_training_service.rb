# frozen_string_literal: true

# ⚠️ DEPRECATED: Agent Lightning Training Service
#
# This service is deprecated in favor of the native learning systems:
#
# 1. ExecutionLearningBridge - Records execution patterns and updates capabilities
# 2. Collaboration::EnergyTracker - Tracks success/failure and updates Elo ratings
# 3. Collaboration::AgentSchool - Diagnoses and trains underperforming agents
# 4. SystemNotificationService - Notifies users of failures and patterns
#
# The native stack provides the same benefits without a Python dependency:
# - Real-time capability updates (immediate, not batch)
# - Integrated with energy/reputation system
# - Automatic school enrollment on failure
# - Pattern detection via ExecutionGuardService
#
# Replacement mapping:
# - record_llm_call -> ExecutionLearningBridge#record_successful_execution
# - execute_training -> AgentSchool#apply_curriculum
# - get_training_traces -> SystemNotification queries
#
# To migrate: Use ExecutionLearningBridge for pattern recording and
# let the Energy System handle capability updates naturally.
#
# This file will be removed in a future release.
#
# Agent Lightning Training Service (DEPRECATED)
# Orchestrates prompt optimization and RL-based agent improvement
class AgentLightningTrainingService
  # @deprecated Use ExecutionLearningBridge and Collaboration::AgentSchool instead
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

  # Execute training via Python Agent Lightning service
  def execute_training(traces = nil)
    traces ||= get_training_traces
    return { success: false, message: "Not enough traces for training" } if traces.empty?

    Rails.logger.info "🚀 Starting Agent Lightning training with #{traces.count} traces"

    # Check if Python service is available
    unless PythonAgentLightningClient.available?
      Rails.logger.error "❌ Python Agent Lightning service not available"
      return {
        success: false,
        message: "Agent Lightning Python service not available - ensure the service is running",
        fallback_used: false
      }
    end

    job = create_training_job(traces)

    begin
      job.update!(status: "running", started_at: Time.current)

      # Prepare training configuration for Python service
      training_config = {
        learning_rate: @config.learning_parameters['learning_rate'] || 0.001,
        batch_size: @config.learning_parameters['batch_size'] || 32,
        num_epochs: @config.learning_parameters['num_epochs'] || 3,
        n_runners: @config.n_runners || 4,
        optimization_targets: @config.optimization_targets
      }

      # Get trace IDs to train on
      trace_ids = traces.pluck(:trace_id)

      # Start training in Python service
      response = PythonAgentLightningClient.start_training(
        @entity.id,
        training_config,
        trace_ids: trace_ids
      )

      python_job_id = response['job_id']
      job.update!(
        metadata: (job.metadata || {}).merge(python_job_id: python_job_id)
      )

      # Wait for training to complete (with timeout)
      result = PythonAgentLightningClient.wait_for_training(
        python_job_id,
        timeout: 1800,  # 30 minutes
        poll_interval: 10
      )

      if result[:success]
        # Mark traces as used
        traces.update_all(included_in_training: true, training_used_at: Time.current)

        # Complete job
        results = result[:results] || {}
        improvement = calculate_improvement_from_results(results)

        job.mark_completed(results, improvement)
        @config.mark_training_completed

        Rails.logger.info "✅ Training completed with #{improvement}% improvement"
        {
          success: true,
          job_id: job.job_id,
          python_job_id: python_job_id,
          traces_used: traces.count,
          improvement: improvement,
          results: results
        }
      else
        raise StandardError, result[:error]
      end

    rescue PythonAgentLightningClient::ServiceUnavailableError => e
      Rails.logger.error "❌ Python service unavailable: #{e.message}"
      job.mark_failed("Python service unavailable: #{e.message}")
      { success: false, error: e.message, job_id: job.job_id }

    rescue PythonAgentLightningClient::TrainingError => e
      Rails.logger.error "❌ Training failed: #{e.message}"
      job.mark_failed(e.message)
      { success: false, error: e.message, job_id: job.job_id }

    rescue => e
      Rails.logger.error "❌ Training failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
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
        optimization_targets: @config.optimization_targets,
        using_python_service: true
      },
      model_config: {
        model: "qwen3-next-80b",  # Cost-efficient for training
        temperature: 0.3
      }
    )
  end

  # Extract improvement metric from Python service results
  def calculate_improvement_from_results(results)
    # Python service should return improvement metrics
    # For now, return 0 if not provided
    results.dig('overall_improvement') || 0
  end

  # Create default config
  def create_default_config
    AgentLightningConfig.create!(
      entity: @entity,
      enabled: true,
      mode: "optimizing",
      training_strategy: "rl_training",  # Using real RL via Python service
      retrain_frequency_hours: 24,
      n_runners: 4
    )
  end
end
