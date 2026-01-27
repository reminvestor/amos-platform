require "test_helper"

class VoiceProviderHealthServiceTest < ActiveSupport::TestCase
  setup do
    @service = VoiceProviderHealthService.new
  end

  # ============================================================================
  # HEALTH CHECK Tests
  # ============================================================================

  test "check_provider_health returns health status for eleven_labs" do
    with_env("ELEVEN_LABS_API_KEY" => "test_key") do
      HTTParty.expects(:get).returns(mock_response(success: true))

      # Use public interface instead of private method
      health = @service.check_provider_health("eleven_labs")

      assert_equal "healthy", health[:status]
      assert_equal "eleven_labs", health[:provider]
      assert health[:available]
      assert health[:latency_ms].is_a?(Integer)
    end
  end

  test "check_provider_health returns health status for deepgram" do
    with_env("DEEPGRAM_API_KEY" => "test_key") do
      HTTParty.expects(:get).returns(mock_response(success: true))

      # Use public interface instead of private method
      health = @service.check_provider_health("deepgram")

      assert_equal "healthy", health[:status]
      assert_equal "deepgram", health[:provider]
      assert health[:available]
    end
  end

  test "check_all_providers_health returns status for all providers" do
    with_env("ELEVEN_LABS_API_KEY" => "test_key", "DEEPGRAM_API_KEY" => "test_key") do
      HTTParty.expects(:get).twice.returns(mock_response(success: true))

      result = @service.check_all_providers_health

      assert result.key?(:timestamp)
      assert result.key?(:eleven_labs)
      assert result.key?(:deepgram)
      assert result.key?(:summary)
    end
  end

  # ============================================================================
  # METRICS Recording Tests
  # ============================================================================

  test "record_successful_connection records metric" do
    @service.record_successful_connection("eleven_labs", 150)

    metrics = @service.get_provider_metrics("eleven_labs")
    assert_equal "eleven_labs", metrics[:provider]
  end

  test "record_failed_connection records failure" do
    @service.record_failed_connection("eleven_labs", "Connection timeout")

    metrics = @service.get_provider_metrics("eleven_labs")
    assert_equal "eleven_labs", metrics[:provider]
  end

  # ============================================================================
  # SUMMARY Tests
  # ============================================================================

  test "get_health_summary includes recommended provider" do
    with_env("ELEVEN_LABS_API_KEY" => "test_key", "DEEPGRAM_API_KEY" => "test_key") do
      HTTParty.expects(:get).twice.returns(mock_response(success: true))

      summary = @service.get_health_summary

      assert summary.key?(:providers)
      assert summary.key?(:recommended_provider)
      assert summary.key?(:timestamp)
    end
  end

  # ============================================================================
  # CIRCUIT BREAKER Tests
  # ============================================================================

  test "is_provider_available? returns true when within threshold" do
    result = @service.is_provider_available?("eleven_labs", failure_threshold: 5)

    assert result
  end

  # ============================================================================
  # ERROR HANDLING Tests
  # ============================================================================

  test "handles HTTP errors gracefully" do
    HTTParty.expects(:get).raises(StandardError.new("Network error"))

    # Use public interface instead of private method
    health = @service.check_provider_health("eleven_labs")

    assert_equal "error", health[:status]
    assert_not health[:available]
    assert health[:error].include?("Network error")
  end

  test "handles timeout errors" do
    HTTParty.expects(:get).raises(Timeout::Error.new)

    # Use public interface instead of private method
    health = @service.check_provider_health("eleven_labs")

    assert_equal "timeout", health[:status]
    assert_not health[:available]
  end

  private

  def mock_response(success: true)
    mock = Minitest::Mock.new
    mock.expect :success?, success
    mock.expect :code, success ? 200 : 500
    mock.expect :message, success ? "OK" : "Error"
    mock
  end

  def with_env(vars)
    original_vars = {}
    vars.each do |key, value|
      original_vars[key] = ENV[key]
      ENV[key] = value
    end

    yield

    original_vars.each do |key, value|
      ENV[key] = value
    end
  end
end
