# ElevenLabsTranscriptionService handles Eleven Labs Scribe v2 API integration for real-time transcription
#
# Responsibilities:
# - Generate WebSocket URLs for Scribe v2 Realtime connections
# - Build WebSocket configuration with optimal parameters
# - Handle real-time transcript streaming
# - Support multiple languages
#
# Features:
# - Ultra-low latency (~150ms) real-time transcription
# - 90+ language support
# - High accuracy across accents and tones
# - Partial and final transcripts
#
# Usage:
#   service = ElevenLabsTranscriptionService.new(voice_session)
#   config = service.websocket_config
#   url = service.websocket_url
class ElevenLabsTranscriptionService
  ELEVEN_LABS_API_URL = "https://api.elevenlabs.io".freeze
  ELEVEN_LABS_WEBSOCKET_URL = "wss://api.elevenlabs.io/v1/convai/conversation".freeze
  DEFAULT_LANGUAGE = "en".freeze
  DEFAULT_MODEL = "scribe-v2-realtime".freeze

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
      # Audio format settings
      encoding: "pcm_16bit", # 16-bit PCM encoding
      sample_rate: 16000, # Telephony quality (16kHz)
      channels: 1,

      # Model and language
      model: DEFAULT_MODEL,
      language: language || DEFAULT_LANGUAGE,

      # Transcription features
      punctuate: true,
      include_partial_results: true,

      # Advanced features
      enable_speaker_diarization: false, # Set to true if speaker identification needed
      enable_sentiment_analysis: false, # Set to true if sentiment detection needed

      # Performance tuning
      latency_optimized: true # Optimized for ~150ms latency
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
