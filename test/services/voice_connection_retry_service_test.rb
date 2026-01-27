require "test_helper"

class VoiceConnectionRetryServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @user.update!(entity: @entity)

    @voice_session = VoiceSession.create!(
      user: @user,
      entity: @entity,
      session_id: SecureRandom.uuid,
      status: "active"
    )

    @service = VoiceConnectionRetryService.new(@voice_session)
  end

  # ============================================================================
  # RETRY LOGIC Tests
  # ============================================================================

  test "connect_with_retries succeeds on first attempt" do
    attempts = 0
    success = @service.connect_with_retries("eleven_labs", {}) do |creds|
      attempts += 1
      true
    end

    assert success
    assert_equal 1, attempts
  end

  test "connect_with_retries retries on failure" do
    attempts = 0
    success = @service.connect_with_retries("eleven_labs", {}) do |creds|
      attempts += 1
      raise StandardError.new("Connection failed") if attempts < 2
      true
    end

    assert success
    assert_equal 2, attempts
  end

  test "connect_with_retries respects max retries" do
    attempts = 0
    success = @service.connect_with_retries("eleven_labs", {}) do |creds|
      attempts += 1
      raise StandardError.new("Always fails")
    end

    assert_not success
    assert attempts > 1
  end

  # ============================================================================
  # BACKOFF Tests
  # ============================================================================

  test "exponential backoff increases with each retry" do
    # Backoff should roughly double each time
    backoff_times = []

    catch :done do
      loop do
        backoff = @service.send(:calculate_backoff, backoff_times.length + 1)
        backoff_times << backoff

        throw :done if backoff_times.length >= 3
      end
    end

    # Each should be greater than the last
    assert backoff_times[1] >= backoff_times[0]
    assert backoff_times[2] >= backoff_times[1]
  end

  # ============================================================================
  # CIRCUIT BREAKER Tests
  # ============================================================================

  test "circuit_breaker_open? returns false initially" do
    result = @service.circuit_breaker_open?("eleven_labs")

    assert_not result
  end

  test "circuit breaker opens after max retries" do
    attempts = 0

    @service.connect_with_retries("eleven_labs", {}) do |creds|
      attempts += 1
      raise StandardError.new("Always fails")
    end

    assert @service.circuit_breaker_open?("eleven_labs")
  end

  # ============================================================================
  # FALLBACK Tests
  # ============================================================================

  test "connect_with_fallback succeeds with primary provider" do
    result = @service.connect_with_fallback(
      "eleven_labs", "deepgram",
      {}, {},
    ) do |provider, creds|
      true
    end

    assert result[:success]
    assert_equal "eleven_labs", result[:provider]
  end

  test "connect_with_fallback falls back to secondary provider" do
    attempts = []

    result = @service.connect_with_fallback(
      "eleven_labs", "deepgram",
      {}, {},
    ) do |provider, creds|
      attempts << provider
      # Service expects exceptions for failure, not false returns
      raise StandardError.new("Connection failed") unless provider == "deepgram"
      true
    end

    assert result[:success]
    assert_equal "deepgram", result[:provider]
    assert attempts.include?("eleven_labs")
    assert attempts.include?("deepgram")
  end

  test "connect_with_fallback returns failure when both fail" do
    result = @service.connect_with_fallback(
      "eleven_labs", "deepgram",
      {}, {},
    ) do |provider, creds|
      raise StandardError.new("Failed")
    end

    assert_not result[:success]
    assert_nil result[:provider]
  end

  # ============================================================================
  # STATISTICS Tests
  # ============================================================================

  test "get_statistics returns retry count" do
    stats = @service.get_statistics

    assert stats.key?(:current_retry_count)
    assert stats.key?(:providers_in_circuit)
    assert stats.key?(:timestamp)
  end

  private
end
