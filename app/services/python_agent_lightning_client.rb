# frozen_string_literal: true

# ⚠️ DEPRECATED: PythonAgentLightningClient
#
# This client is deprecated. The Python Agent Lightning service is no longer needed.
#
# The native Rails stack now handles all training/learning:
#
# 1. ExecutionLearningBridge - Pattern recording and capability updates
# 2. Collaboration::AgentSchool - Agent diagnosis and curriculum
# 3. Collaboration::EnergyTracker - Real-time Elo rating and energy management
# 4. SystemNotificationService - Failure tracking and user notifications
#
# Benefits of native approach:
# - No Python service dependency
# - Real-time updates (not batch training)
# - Better integrated with platform
# - Simpler deployment
#
# The Python service can be shut down. This file will be removed in a future release.
#
# Client for communicating with the Python Agent Lightning service (DEPRECATED)
# This service provides a Rails interface to the real Agent Lightning training system
class PythonAgentLightningClient
  # @deprecated The Python service is no longer needed
  BASE_URL = ENV['AGENT_LIGHTNING_SERVICE_URL'] || 'http://localhost:4747'

  class ServiceUnavailableError < StandardError; end
  class TrainingError < StandardError; end

  class << self
    # Check if the Python service is available
    def available?
      ENV['AGENT_LIGHTNING_ENABLED'] == 'true' && service_healthy?
    end

    # Check service health
    def service_healthy?
      response = HTTParty.get("#{BASE_URL}/health", timeout: 5)
      response.success? && response.parsed_response['agent_lightning_available']
    rescue => e
      Rails.logger.warn("Agent Lightning service health check failed: #{e.message}")
      false
    end

    # Create a rollout in the Store
    def create_rollout(rollout_data)
      raise ServiceUnavailableError unless available?

      response = HTTParty.post(
        "#{BASE_URL}/api/rollouts",
        body: rollout_data.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: 30
      )

      handle_response(response)
    rescue HTTParty::Error, Timeout::Error => e
      Rails.logger.error("Failed to create rollout: #{e.message}")
      raise ServiceUnavailableError, "Python service unavailable: #{e.message}"
    end

    # Add a span to an existing rollout
    def add_span(rollout_id, attempt_id, span_data)
      raise ServiceUnavailableError unless available?

      response = HTTParty.post(
        "#{BASE_URL}/api/spans",
        body: {
          rollout_id: rollout_id,
          attempt_id: attempt_id,
          span: span_data
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: 10
      )

      handle_response(response)
    rescue HTTParty::Error, Timeout::Error => e
      Rails.logger.error("Failed to add span: #{e.message}")
      # Don't raise - spans are non-critical
      nil
    end

    # Start a training job
    def start_training(entity_id, config, trace_ids: nil)
      raise ServiceUnavailableError unless available?

      Rails.logger.info("🚀 Starting Agent Lightning training for entity #{entity_id}")

      response = HTTParty.post(
        "#{BASE_URL}/api/training/start",
        body: {
          entity_id: entity_id,
          config: config,
          trace_ids: trace_ids
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: 60
      )

      result = handle_response(response)
      Rails.logger.info("✅ Training job started: #{result['job_id']}")
      result
    rescue HTTParty::Error, Timeout::Error => e
      Rails.logger.error("Failed to start training: #{e.message}")
      raise TrainingError, "Failed to start training: #{e.message}"
    end

    # Get training job status
    def get_training_status(job_id)
      raise ServiceUnavailableError unless available?

      response = HTTParty.get(
        "#{BASE_URL}/api/training/#{job_id}/status",
        timeout: 10
      )

      handle_response(response)
    rescue HTTParty::Error, Timeout::Error => e
      Rails.logger.error("Failed to get training status: #{e.message}")
      raise ServiceUnavailableError, "Python service unavailable: #{e.message}"
    end

    # List all training jobs
    def list_training_jobs
      raise ServiceUnavailableError unless available?

      response = HTTParty.get(
        "#{BASE_URL}/api/training/jobs",
        timeout: 10
      )

      handle_response(response)
    rescue HTTParty::Error, Timeout::Error => e
      Rails.logger.error("Failed to list training jobs: #{e.message}")
      { jobs: [], total: 0 }
    end

    # Wait for training job to complete (with timeout)
    def wait_for_training(job_id, timeout: 600, poll_interval: 5)
      start_time = Time.current
      loop do
        status = get_training_status(job_id)

        case status['status']
        when 'completed'
          return { success: true, results: status['results'] }
        when 'failed'
          return { success: false, error: status['error'] }
        when 'running', 'queued'
          # Continue polling
          if Time.current - start_time > timeout
            return { success: false, error: "Training timeout after #{timeout}s" }
          end
          sleep poll_interval
        else
          return { success: false, error: "Unknown status: #{status['status']}" }
        end
      end
    end

    # Phase 6: Get optimized prompts from a training job
    def get_optimized_prompts(job_id)
      raise ServiceUnavailableError unless available?

      response = HTTParty.get(
        "#{BASE_URL}/api/training/#{job_id}/optimized-prompts",
        timeout: 10
      )

      handle_response(response)
    rescue HTTParty::Error, Timeout::Error => e
      Rails.logger.error("Failed to get optimized prompts: #{e.message}")
      raise ServiceUnavailableError, "Python service unavailable: #{e.message}"
    end

    # Stop a running training job
    def stop_training(job_id)
      raise ServiceUnavailableError unless available?

      response = HTTParty.post(
        "#{BASE_URL}/api/training/#{job_id}/stop",
        timeout: 30
      )

      result = handle_response(response)
      { success: true, message: result['message'] || 'Training stopped' }
    rescue HTTParty::Error, Timeout::Error => e
      Rails.logger.error("Failed to stop training: #{e.message}")
      { success: false, error: e.message }
    rescue TrainingError => e
      { success: false, error: e.message }
    end

    # Rollback an optimization
    def rollback_optimization(optimization_id)
      raise ServiceUnavailableError unless available?

      response = HTTParty.post(
        "#{BASE_URL}/api/optimizations/#{optimization_id}/rollback",
        timeout: 30
      )

      result = handle_response(response)
      { success: true, message: result['message'] || 'Rollback successful' }
    rescue HTTParty::Error, Timeout::Error => e
      Rails.logger.error("Failed to rollback optimization: #{e.message}")
      { success: false, error: e.message }
    rescue TrainingError => e
      { success: false, error: e.message }
    end

    # Health check with detailed status
    def health_check
      response = HTTParty.get("#{BASE_URL}/health", timeout: 5)
      if response.success?
        {
          status: 'healthy',
          version: response.parsed_response['version'],
          agent_lightning_available: response.parsed_response['agent_lightning_available']
        }
      else
        { status: 'unhealthy', error: response.message }
      end
    rescue => e
      { status: 'unavailable', error: e.message }
    end

    private

    def handle_response(response)
      if response.success?
        response.parsed_response
      else
        error_msg = response.parsed_response&.dig('detail') || response.message
        Rails.logger.error("Python service error: #{error_msg}")
        raise TrainingError, error_msg
      end
    end
  end
end
