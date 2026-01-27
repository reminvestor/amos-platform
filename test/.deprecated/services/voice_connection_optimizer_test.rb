require "test_helper"

class VoiceConnectionOptimizerTest < ActiveSupport::TestCase
  setup do
    @optimizer = VoiceConnectionOptimizer.new
  end

  # ============================================================================
  # CREDENTIAL CACHING Tests
  # ============================================================================

  test "get_or_cache_credentials returns credentials" do
    with_env("ELEVEN_LABS_API_KEY" => "test_key") do
      creds = @optimizer.get_or_cache_credentials("eleven_labs")

      assert creds.is_a?(Hash)
      assert creds.key?(:api_key)
      assert_equal "test_key", creds[:api_key]
    end
  end

  test "get_or_cache_credentials uses cache on subsequent calls" do
    with_env("ELEVEN_LABS_API_KEY" => "test_key") do
      creds1 = @optimizer.get_or_cache_credentials("eleven_labs")
      creds2 = @optimizer.get_or_cache_credentials("eleven_labs")

      # Should be identical (same cache)
      assert_equal creds1, creds2
    end
  end

  test "has_valid_cached_credentials? returns true when cached" do
    with_env("ELEVEN_LABS_API_KEY" => "test_key") do
      @optimizer.get_or_cache_credentials("eleven_labs")

      assert @optimizer.has_valid_cached_credentials?("eleven_labs")
    end
  end

  test "has_valid_cached_credentials? returns false when not cached" do
    result = @optimizer.has_valid_cached_credentials?("eleven_labs")

    assert_not result
  end

  # ============================================================================
  # CACHE MANAGEMENT Tests
  # ============================================================================

  test "clear_credential_cache removes cached credentials" do
    with_env("ELEVEN_LABS_API_KEY" => "test_key") do
      @optimizer.get_or_cache_credentials("eleven_labs")
      assert @optimizer.has_valid_cached_credentials?("eleven_labs")

      @optimizer.clear_credential_cache("eleven_labs")
      assert_not @optimizer.has_valid_cached_credentials?("eleven_labs")
    end
  end

  test "clear_credential_cache without provider clears all" do
    with_env("ELEVEN_LABS_API_KEY" => "key1", "DEEPGRAM_API_KEY" => "key2") do
      @optimizer.get_or_cache_credentials("eleven_labs")
      @optimizer.get_or_cache_credentials("deepgram")

      @optimizer.clear_credential_cache

      assert_not @optimizer.has_valid_cached_credentials?("eleven_labs")
      assert_not @optimizer.has_valid_cached_credentials?("deepgram")
    end
  end

  # ============================================================================
  # CACHE STATISTICS Tests
  # ============================================================================

  test "get_cache_statistics returns cache status" do
    with_env("ELEVEN_LABS_API_KEY" => "test_key") do
      @optimizer.get_or_cache_credentials("eleven_labs")

      stats = @optimizer.get_cache_statistics

      assert stats.key?(:timestamp)
      assert stats.key?(:cached_providers)
      assert stats.key?(:total_cached)
    end
  end

  # ============================================================================
  # PRE-WARMING Tests
  # ============================================================================

  test "prewarm_connections returns results" do
    with_env("ELEVEN_LABS_API_KEY" => "key", "DEEPGRAM_API_KEY" => "key") do
      VoiceProviderHealthService.any_instance.expects(:check_provider_health).twice.returns(
        { available: true, status: "healthy" }
      )

      results = @optimizer.prewarm_connections

      assert results.key?(:timestamp)
      assert results.key?(:providers)
    end
  end

  # ============================================================================
  # OPTIMIZATION METRICS Tests
  # ============================================================================

  test "get_optimization_metrics returns recommendations" do
    with_env("ELEVEN_LABS_API_KEY" => "key", "DEEPGRAM_API_KEY" => "key") do
      VoiceProviderHealthService.any_instance.expects(:check_all_providers_health).returns(
        { eleven_labs: { available: true }, deepgram: { available: true } }
      )

      metrics = @optimizer.get_optimization_metrics

      assert metrics.key?(:timestamp)
      assert metrics.key?(:optimization_metrics)
      assert metrics.key?(:cache_statistics)
      assert metrics.key?(:recommendations)
    end
  end

  # ============================================================================
  # CONNECTION POOL Tests
  # ============================================================================

  test "get_connection_pool_status returns pool statistics" do
    status = @optimizer.get_connection_pool_status("eleven_labs")

    assert_equal "eleven_labs", status[:provider]
    assert status.key?(:pool_size)
    assert status.key?(:active_connections)
    assert status.key?(:idle_connections)
    assert status.key?(:utilization_percent)
  end

  private

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
