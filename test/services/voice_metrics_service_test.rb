require "test_helper"

class VoiceMetricsServiceTest < ActiveSupport::TestCase
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

    @service = VoiceMetricsService.new
  end

  # ============================================================================
  # METRIC RECORDING Tests
  # ============================================================================

  test "record_session_metric stores metric data" do
    metric = @service.record_session_metric(
      @voice_session,
      "eleven_labs",
      connection_time_ms: 150,
      duration_seconds: 10,
      success: true
    )

    assert_equal @voice_session.session_id, metric[:session_id]
    assert_equal "eleven_labs", metric[:provider]
    assert_equal 150, metric[:connection_time_ms]
    assert metric[:success]
  end

  test "record_session_metric marks fallback usage" do
    metric = @service.record_session_metric(
      @voice_session,
      "deepgram",
      fallback_used: true,
      connection_time_ms: 200
    )

    assert metric[:fallback_used]
  end

  # ============================================================================
  # STATISTICS Tests
  # ============================================================================

  test "get_provider_statistics returns statistics object" do
    # Record some metrics
    3.times do |i|
      @service.record_session_metric(
        @voice_session,
        "eleven_labs",
        connection_time_ms: 100 + i * 10,
        success: i < 2  # 2 successes, 1 failure
      )
    end

    stats = @service.get_provider_statistics("eleven_labs", days: 1)

    assert_equal "eleven_labs", stats[:provider]
    assert stats.key?(:total_sessions)
    assert stats.key?(:successful_sessions)
    assert stats.key?(:failed_sessions)
    assert stats.key?(:success_rate_percent)
    assert stats.key?(:avg_connection_time_ms)
  end

  test "get_provider_statistics calculates success rate" do
    # Record 4 sessions: 3 success, 1 failure
    4.times do |i|
      @service.record_session_metric(
        @voice_session,
        "eleven_labs",
        success: i < 3
      )
    end

    stats = @service.get_provider_statistics("eleven_labs", days: 1)

    assert stats[:success_rate_percent] > 0
    assert_equal 3, stats[:successful_sessions]
    assert_equal 1, stats[:failed_sessions]
  end

  # ============================================================================
  # COMPARISON Tests
  # ============================================================================

  test "compare_providers returns comparison data" do
    # Record metrics for both providers
    @service.record_session_metric(@voice_session, "eleven_labs", success: true, connection_time_ms: 100)
    @service.record_session_metric(@voice_session, "deepgram", success: true, connection_time_ms: 200)

    comparison = @service.compare_providers("eleven_labs", "deepgram", days: 1)

    assert comparison.key?(:provider1)
    assert comparison.key?(:provider2)
    assert comparison.key?(:winner)
    assert comparison.key?(:recommendation)
  end

  # ============================================================================
  # ENTITY REPORT Tests
  # ============================================================================

  test "get_entity_usage_report returns usage statistics" do
    @service.record_session_metric(@voice_session, "eleven_labs", success: true)
    @service.record_session_metric(@voice_session, "deepgram", success: true)

    report = @service.get_entity_usage_report(@entity.id, days: 1)

    assert_equal @entity.id, report[:entity_id]
    assert report.key?(:total_sessions)
    assert report.key?(:provider_breakdown)
  end

  # ============================================================================
  # RECENT SESSIONS Tests
  # ============================================================================

  test "get_recent_sessions returns recent activity" do
    @service.record_session_metric(@voice_session, "eleven_labs")

    sessions = @service.get_recent_sessions(limit: 10)

    assert sessions.is_a?(Array)
  end

  # ============================================================================
  # HEALTH CHECK Tests
  # ============================================================================

  test "check_voice_system_health includes alerts" do
    health = @service.check_voice_system_health

    assert health.key?(:timestamp)
    assert health.key?(:seven_day_stats)
    assert health.key?(:one_day_stats)
    assert health.key?(:alerts)
  end

  private
end
