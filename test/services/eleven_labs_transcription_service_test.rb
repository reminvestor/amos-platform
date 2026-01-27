require "test_helper"

class ElevenLabsTranscriptionServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @voice_session = VoiceSession.create!(
      user: @user,
      entity: @entity,
      session_id: SecureRandom.uuid
    )
    @service = ElevenLabsTranscriptionService.new(@voice_session)
  end

  # ============================================================================
  # Configuration Tests
  # ============================================================================

  test "websocket_config returns valid configuration" do
    config = @service.websocket_config

    assert config.is_a?(Hash), "Config should be a Hash"
    assert_equal "pcm_16000", config[:encoding], "Should use PCM 16kHz encoding"
    assert_equal 16000, config[:sample_rate], "Should use 16kHz sample rate"
    assert_equal 1, config[:channels], "Should use mono channel"
    assert_equal "scribe-v3-realtime", config[:model], "Should use Scribe v3 Realtime model"
    assert_equal "en", config[:language], "Should default to English"
    assert config[:punctuate], "Should enable punctuation"
    assert config[:include_partial_results], "Should enable partial results"
    assert config[:latency_optimized], "Should be optimized for latency"
  end

  test "websocket_config accepts custom language" do
    config = @service.websocket_config(language: "es")

    assert_equal "es", config[:language], "Should use provided language"
  end

  test "websocket_config includes keywords when provided" do
    keywords = ["Acme Corp", "John Smith", "Q3 Results"]
    config = @service.websocket_config(keywords: keywords)

    assert config.key?(:keywords), "Should include keywords in config"
    assert_equal keywords, config[:keywords], "Keywords should match provided values"
  end

  test "websocket_config deduplicates keywords" do
    keywords = ["Acme Corp", "John Smith", "Acme Corp"]
    config = @service.websocket_config(keywords: keywords)

    assert_equal 2, config[:keywords].length, "Should deduplicate keywords"
  end

  test "websocket_config ignores nil keywords" do
    keywords = ["Acme Corp", nil, "John Smith", nil]
    config = @service.websocket_config(keywords: keywords)

    assert config[:keywords].none?(&:nil?), "Should filter out nil keywords"
  end

  # ============================================================================
  # Connection Parameters Tests
  # ============================================================================

  test "connection_params returns complete connection data" do
    with_env("ELEVEN_LABS_API_KEY" => "test_key_12345") do
      params = @service.connection_params

      assert params.is_a?(Hash), "Params should be a Hash"
      assert params.key?(:websocket_url), "Should include websocket_url"
      assert params.key?(:api_key), "Should include api_key"
      assert params.key?(:config), "Should include config"

      assert_equal "test_key_12345", params[:api_key], "API key should match environment"
      assert params[:websocket_url].start_with?("wss://"), "URL should be secure WebSocket"
    end
  end

  test "connection_params includes full configuration" do
    with_env("ELEVEN_LABS_API_KEY" => "test_key_12345") do
      params = @service.connection_params
      config = params[:config]

      assert_equal "pcm_16000", config[:encoding], "Config should include encoding"
      assert_equal 16000, config[:sample_rate], "Config should include sample rate"
      assert_equal "scribe-v2-realtime", config[:model], "Config should include model"
    end
  end

  # ============================================================================
  # API Key Tests
  # ============================================================================

  test "raises error when API key not configured" do
    with_env("ELEVEN_LABS_API_KEY" => nil) do
      service = ElevenLabsTranscriptionService.new(@voice_session)

      assert_raises(RuntimeError) do
        service.connection_params
      end
    end
  end

  test "uses environment variable for API key" do
    with_env("ELEVEN_LABS_API_KEY" => "env_key_test") do
      params = @service.connection_params

      assert_equal "env_key_test", params[:api_key], "Should use environment variable"
    end
  end

  # ============================================================================
  # Supported Languages Tests
  # ============================================================================

  test "supported_languages returns array of language hashes" do
    languages = ElevenLabsTranscriptionService.supported_languages

    assert languages.is_a?(Array), "Should return an array"
    assert languages.length > 0, "Should have at least one language"

    first_language = languages.first
    assert first_language.key?(:code), "Language should have a code"
    assert first_language.key?(:name), "Language should have a name"
  end

  test "supported_languages includes major languages" do
    languages = ElevenLabsTranscriptionService.supported_languages
    language_codes = languages.map { |l| l[:code] }

    assert language_codes.include?("en"), "Should support English"
    assert language_codes.include?("es"), "Should support Spanish"
    assert language_codes.include?("fr"), "Should support French"
    assert language_codes.include?("de"), "Should support German"
  end

  test "supported_languages includes Hindi for Indian language support" do
    languages = ElevenLabsTranscriptionService.supported_languages
    hindi = languages.find { |l| l[:code] == "hi" }

    assert_not_nil hindi, "Should support Hindi"
    assert_equal "Hindi", hindi[:name], "Language name should be correct"
  end

  # ============================================================================
  # Connection Test Tests
  # ============================================================================

  test "test_connection returns false when API key not configured" do
    with_env("ELEVEN_LABS_API_KEY" => nil) do
      result = ElevenLabsTranscriptionService.test_connection

      assert_equal false, result, "Should return false when API key missing"
    end
  end

  test "test_connection handles HTTP errors gracefully" do
    with_env("ELEVEN_LABS_API_KEY" => "test_key") do
      # Mock HTTParty to return a failed response
      HTTParty.expects(:get).raises(StandardError.new("Network error"))

      result = ElevenLabsTranscriptionService.test_connection

      assert_equal false, result, "Should return false on error"
    end
  end

  # ============================================================================
  # Voice Session Integration Tests
  # ============================================================================

  test "service stores voice session reference" do
    assert_equal @voice_session, @service.voice_session
  end

  test "service works with provided keywords" do
    # VoiceSession no longer has keywords attribute, just test with provided keywords
    config = @service.websocket_config(keywords: ["Acme Corp", "Q4 Earnings", "New Keyword"])
    keywords = config[:keywords]

    assert keywords.include?("Acme Corp"), "Should include keyword Acme Corp"
    assert keywords.include?("Q4 Earnings"), "Should include keyword Q4 Earnings"
    assert keywords.include?("New Keyword"), "Should include keyword New Keyword"
  end

  # ============================================================================
  # Encoding and Audio Format Tests
  # ============================================================================

  test "websocket_config specifies correct audio format for browser compatibility" do
    config = @service.websocket_config

    # PCM 16kHz is telephony standard and widely supported
    assert_equal "pcm_16000", config[:encoding]
    assert_equal 16000, config[:sample_rate]
    assert_equal 1, config[:channels]
  end

  test "websocket_config enables features for real-time transcription" do
    config = @service.websocket_config

    # These features are critical for real-time STT
    assert config[:punctuate], "Should enable punctuation for readability"
    assert config[:include_partial_results], "Should enable partial results for responsiveness"
    assert config[:latency_optimized], "Should optimize for low latency"
  end

  # ============================================================================
  # Constants Tests
  # ============================================================================

  test "service defines correct Eleven Labs WebSocket URL" do
    assert_equal "wss://api.elevenlabs.io/v1/scribe/v3/realtime",
                 ElevenLabsTranscriptionService::ELEVEN_LABS_WEBSOCKET_URL
  end

  test "service defines correct default model" do
    assert_equal "scribe-v3-realtime",
                 ElevenLabsTranscriptionService::DEFAULT_MODEL
  end

  test "service defines correct default language" do
    assert_equal "en",
                 ElevenLabsTranscriptionService::DEFAULT_LANGUAGE
  end

  private

  def with_env(vars)
    original_vars = {}
    vars.each do |key, value|
      original_vars[key] = ENV[key]
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    yield

    original_vars.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
