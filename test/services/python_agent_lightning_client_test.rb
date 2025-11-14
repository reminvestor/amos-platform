require "test_helper"

class PythonAgentLightningClientTest < ActiveSupport::TestCase
  setup do
    # Mock environment
    ENV['AGENT_LIGHTNING_ENABLED'] = 'true'
    ENV['AGENT_LIGHTNING_SERVICE_URL'] = 'http://localhost:4747'
  end

  teardown do
    ENV['AGENT_LIGHTNING_ENABLED'] = nil
  end

  # available? tests
  test "available? returns true when enabled and service is healthy" do
    stub_health_check(true)
    assert PythonAgentLightningClient.available?
  end

  test "available? returns false when disabled" do
    ENV['AGENT_LIGHTNING_ENABLED'] = 'false'
    assert_not PythonAgentLightningClient.available?
  end

  test "available? returns false when service is unhealthy" do
    stub_health_check(false)
    assert_not PythonAgentLightningClient.available?
  end

  # service_healthy? tests
  test "service_healthy? returns true for successful health check" do
    stub_health_check(true)
    assert PythonAgentLightningClient.send(:service_healthy?)
  end

  test "service_healthy? returns false for failed health check" do
    stub_health_check(false)
    assert_not PythonAgentLightningClient.send(:service_healthy?)
  end

  test "service_healthy? handles connection errors gracefully" do
    HTTParty.stub(:get, -> { raise StandardError.new("Connection refused") }) do
      assert_not PythonAgentLightningClient.send(:service_healthy?)
    end
  end

  # create_rollout tests
  test "create_rollout sends correct request" do
    stub_health_check(true)
    rollout_data = { trace_id: "test-123", timestamp: Time.current.to_i }

    response_body = { success: true, rollout_id: "rollout-123" }
    stub_http_response("http://localhost:4747/api/rollouts", response_body, :post)

    result = PythonAgentLightningClient.create_rollout(rollout_data)

    assert_equal "rollout-123", result['rollout_id']
  end

  test "create_rollout raises when service unavailable" do
    stub_health_check(false)

    assert_raises(PythonAgentLightningClient::ServiceUnavailableError) do
      PythonAgentLightningClient.create_rollout({})
    end
  end

  # add_span tests
  test "add_span sends span data correctly" do
    stub_health_check(true)
    span_data = { name: "llm_call", type: "llm_call", model: "claude-3.5-sonnet" }

    response_body = { success: true, span_id: "span-123" }
    stub_http_response("http://localhost:4747/api/spans", response_body, :post)

    result = PythonAgentLightningClient.add_span("rollout-123", 0, span_data)

    assert_equal "span-123", result['span_id']
  end

  test "add_span returns nil on error (non-critical)" do
    stub_health_check(true)
    HTTParty.stub(:post, -> { raise StandardError.new("Network error") }) do
      result = PythonAgentLightningClient.add_span("rollout-123", 0, {})
      assert_nil result
    end
  end

  # start_training tests
  test "start_training sends training request" do
    stub_health_check(true)
    entity_id = 1
    config = { mode: "optimizing" }

    response_body = { job_id: "job-123", status: "queued" }
    stub_http_response("http://localhost:4747/api/training/start", response_body, :post)

    result = PythonAgentLightningClient.start_training(entity_id, config)

    assert_equal "job-123", result['job_id']
  end

  test "start_training raises TrainingError on failure" do
    stub_health_check(true)
    HTTParty.stub(:post, -> { raise StandardError.new("Training failed") }) do
      assert_raises(PythonAgentLightningClient::TrainingError) do
        PythonAgentLightningClient.start_training(1, {})
      end
    end
  end

  # get_training_status tests
  test "get_training_status retrieves job status" do
    stub_health_check(true)
    response_body = { status: "running", progress: 0.5 }
    stub_http_response("http://localhost:4747/api/training/job-123/status", response_body, :get)

    result = PythonAgentLightningClient.get_training_status("job-123")

    assert_equal "running", result['status']
    assert_equal 0.5, result['progress']
  end

  test "get_training_status raises when service unavailable" do
    stub_health_check(false)

    assert_raises(PythonAgentLightningClient::ServiceUnavailableError) do
      PythonAgentLightningClient.get_training_status("job-123")
    end
  end

  # list_training_jobs tests
  test "list_training_jobs returns job list" do
    stub_health_check(true)
    response_body = { jobs: [{ id: "job-1" }, { id: "job-2" }], total: 2 }
    stub_http_response("http://localhost:4747/api/training/jobs", response_body, :get)

    result = PythonAgentLightningClient.list_training_jobs

    assert_equal 2, result['total']
    assert_equal 2, result['jobs'].length
  end

  test "list_training_jobs returns empty list on error" do
    stub_health_check(true)
    HTTParty.stub(:get, -> { raise StandardError.new("Service error") }) do
      result = PythonAgentLightningClient.list_training_jobs
      assert_equal 0, result['total']
      assert_empty result['jobs']
    end
  end

  # Phase 5: get_optimized_prompts tests
  test "get_optimized_prompts retrieves optimized prompts from training" do
    stub_health_check(true)
    response_body = {
      optimized_prompts: {
        gather_context: "Optimized prompt for gathering context",
        execute_goal: "Optimized prompt for executing goal"
      },
      improvement_percentage: 12.5,
      training_metrics: {
        success_rate: 0.95,
        avg_tokens: 1500
      }
    }
    stub_http_response("http://localhost:4747/api/training/job-123/optimized-prompts", response_body, :get)

    result = PythonAgentLightningClient.get_optimized_prompts("job-123")

    assert result['optimized_prompts'].present?
    assert_equal 12.5, result['improvement_percentage']
    assert_equal 0.95, result['training_metrics']['success_rate']
  end

  test "get_optimized_prompts raises when service unavailable" do
    stub_health_check(false)

    assert_raises(PythonAgentLightningClient::ServiceUnavailableError) do
      PythonAgentLightningClient.get_optimized_prompts("job-123")
    end
  end

  test "get_optimized_prompts handles timeout gracefully" do
    stub_health_check(true)
    HTTParty.stub(:get, -> { raise Timeout::Error.new("Request timeout") }) do
      assert_raises(PythonAgentLightningClient::ServiceUnavailableError) do
        PythonAgentLightningClient.get_optimized_prompts("job-123")
      end
    end
  end

  test "get_optimized_prompts handles HTTP errors gracefully" do
    stub_health_check(true)
    HTTParty.stub(:get, -> { raise HTTParty::Error.new("HTTP error") }) do
      assert_raises(PythonAgentLightningClient::ServiceUnavailableError) do
        PythonAgentLightningClient.get_optimized_prompts("job-123")
      end
    end
  end

  # wait_for_training tests
  test "wait_for_training returns results when job completes" do
    stub_health_check(true)
    responses = [
      { status: "running" },
      { status: "running" },
      { status: "completed", results: { optimization_id: "opt-123" } }
    ]
    call_count = [0]

    PythonAgentLightningClient.stub(:get_training_status, lambda { |job_id|
      result = responses[call_count[0]]
      call_count[0] += 1
      result
    }) do
      result = PythonAgentLightningClient.wait_for_training("job-123", timeout: 30, poll_interval: 0)

      assert result[:success]
      assert_equal "opt-123", result[:results]['optimization_id']
    end
  end

  test "wait_for_training returns error when job fails" do
    stub_health_check(true)

    PythonAgentLightningClient.stub(:get_training_status, -> {
      { status: "failed", error: "Training crashed" }
    }) do
      result = PythonAgentLightningClient.wait_for_training("job-123", timeout: 30, poll_interval: 0)

      assert_not result[:success]
      assert_equal "Training crashed", result[:error]
    end
  end

  test "wait_for_training times out after specified duration" do
    stub_health_check(true)

    PythonAgentLightningClient.stub(:get_training_status, -> {
      { status: "running" }
    }) do
      start_time = Time.current
      result = PythonAgentLightningClient.wait_for_training("job-123", timeout: 1, poll_interval: 0.5)

      assert_not result[:success]
      assert_match(/timeout/i, result[:error])
      assert Time.current - start_time >= 1
    end
  end

  private

  def stub_health_check(healthy)
    response_body = {
      agent_lightning_available: healthy,
      status: healthy ? "healthy" : "unhealthy"
    }
    stub_http_response("http://localhost:4747/health", response_body, :get)
  end

  def stub_http_response(url, body, method = :get)
    response_mock = Minitest::Mock.new
    response_mock.expect(:success?, true)
    response_mock.expect(:parsed_response, body)
    response_mock.expect(:message, "OK")

    HTTParty.stub(method, ->(url_arg, **options) {
      response_mock
    }) do
      yield if block_given?
    end
  end
end
