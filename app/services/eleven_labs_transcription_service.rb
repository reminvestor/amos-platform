# ElevenLabsTranscriptionService handles Eleven Labs Scribe v3 API integration for real-time transcription
#
# Responsibilities:
# - Generate WebSocket URLs for Scribe v3 Realtime connections
# - Build WebSocket configuration with optimal parameters
# - Handle real-time transcript streaming
# - Support multiple languages
#
# Features:
# - Ultra-low latency (~100ms) real-time transcription with v3
# - 100+ language support
# - Enhanced accuracy across accents and tones
# - Partial and final transcripts with improved punctuation
#
# Usage:
#   service = ElevenLabsTranscriptionService.new(voice_session)
#   config = service.websocket_config
#   url = service.websocket_url
class ElevenLabsTranscriptionService
  ELEVEN_LABS_API_URL = "https://api.elevenlabs.io".freeze
  ELEVEN_LABS_WEBSOCKET_URL = "wss://api.elevenlabs.io/v1/scribe/v3/realtime".freeze
  DEFAULT_LANGUAGE = "en".freeze
  DEFAULT_MODEL = "scribe-v3-realtime".freeze
  DEFAULT_ENCODING = "pcm_16000".freeze
  DEFAULT_SAMPLE_RATE = 16000
  DEFAULT_CHANNELS = 1

  attr_reader :voice_session

  def initialize(voice_session)
    @voice_session = voice_session
  end

  # Generate complete WebSocket configuration for Eleven Labs Scribe v2
  #
  # @param language [String] Language code (default: en)
  # @param keywords [Array<String>] Keywords for boosting recognition
  # @return [Hash] WebSocket configuration
  def websocket_config(language: nil, keywords: [])
    config = {
      # Audio format settings (configurable for different quality needs)
      encoding: ENV.fetch("ELEVEN_LABS_ENCODING", DEFAULT_ENCODING),
      sample_rate: ENV.fetch("ELEVEN_LABS_SAMPLE_RATE", DEFAULT_SAMPLE_RATE.to_s).to_i,
      channels: ENV.fetch("ELEVEN_LABS_CHANNELS", DEFAULT_CHANNELS.to_s).to_i,

      # Model and language
      model: ENV.fetch("ELEVEN_LABS_MODEL", DEFAULT_MODEL),
      language: language || ENV.fetch("ELEVEN_LABS_LANGUAGE", DEFAULT_LANGUAGE),

      # Transcription features
      punctuate: ENV.fetch("ELEVEN_LABS_PUNCTUATE", "true") == "true",
      include_partial_results: ENV.fetch("ELEVEN_LABS_PARTIAL_RESULTS", "true") == "true",

      # Advanced features
      enable_speaker_diarization: ENV.fetch("ELEVEN_LABS_SPEAKER_DIARIZATION", "false") == "true",
      enable_sentiment_analysis: ENV.fetch("ELEVEN_LABS_SENTIMENT_ANALYSIS", "false") == "true",

      # Performance tuning
      latency_optimized: ENV.fetch("ELEVEN_LABS_LATENCY_OPTIMIZED", "true") == "true",

      # Timeout settings
      max_duration: ENV.fetch("ELEVEN_LABS_MAX_DURATION", "300").to_i,
      silence_timeout: ENV.fetch("ELEVEN_LABS_SILENCE_TIMEOUT", "20").to_i
    }

    # Add keywords for improved recognition (if provided)
    session_keywords = voice_session.keywords
    all_keywords = (keywords + session_keywords).uniq.compact

    if all_keywords.any?
      config[:keywords] = all_keywords
    end

    config
  end

  # Generate WebSocket URL with authentication
  #
  # @return [Hash] Hash with websocket_url, api_key, and config
  def connection_params
    {
      websocket_url: ELEVEN_LABS_WEBSOCKET_URL,
      api_key: eleven_labs_api_key,
      config: websocket_config
    }
  end

  # Get supported languages
  #
  # @return [Array<Hash>] List of supported languages
  def self.supported_languages
    [
      { code: "en", name: "English" },
      { code: "es", name: "Spanish" },
      { code: "fr", name: "French" },
      { code: "de", name: "German" },
      { code: "it", name: "Italian" },
      { code: "pt", name: "Portuguese" },
      { code: "nl", name: "Dutch" },
      { code: "ru", name: "Russian" },
      { code: "ja", name: "Japanese" },
      { code: "zh", name: "Mandarin Chinese" },
      { code: "ar", name: "Arabic" },
      { code: "hi", name: "Hindi" },
      # ... more languages supported by Eleven Labs Scribe v2 (90+)
    ]
  end

  # Verify API key is valid by making a test request
  #
  # @return [Boolean] True if API key is valid
  def self.test_connection
    api_key = ENV["ELEVEN_LABS_API_KEY"]
    return false if api_key.blank?

    response = HTTParty.get(
      "#{ELEVEN_LABS_API_URL}/v1/user",
      headers: {
        "xi-api-key" => api_key
      }
    )

    response.success?
  rescue => e
    Rails.logger.error("Eleven Labs connection test failed: #{e.message}")
    false
  end

  private

  def eleven_labs_api_key
    ENV["ELEVEN_LABS_API_KEY"] ||
      Rails.application.credentials.dig(:eleven_labs, :api_key) ||
      raise("Eleven Labs API key not configured. Set ELEVEN_LABS_API_KEY environment variable or configure via Rails credentials.")
  end
end
