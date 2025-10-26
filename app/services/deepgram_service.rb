# DeepgramService handles Deepgram API integration for voice assistant
#
# Responsibilities:
# - Generate ephemeral API keys for client-side WebSocket connections
# - Build WebSocket configuration with keyword boosting
# - Validate webhook signatures from Deepgram
#
# Usage:
#   service = DeepgramService.new(voice_session)
#   key = service.generate_ephemeral_key(ttl_minutes: 15)
#   config = service.websocket_config(keywords: ['John Smith', 'Acme Corp'])
class DeepgramService
  DEEPGRAM_API_URL = "https://api.deepgram.com/v1".freeze
  DEFAULT_TTL_MINUTES = 15
  DEFAULT_MODEL = "nova-3".freeze
  DEFAULT_LANGUAGE = "en-US".freeze

  attr_reader :voice_session

  def initialize(voice_session)
    @voice_session = voice_session
  end

  # Generate ephemeral Deepgram API key for client-side use
  #
  # @param ttl_minutes [Integer] Time-to-live in minutes (default: 15)
  # @return [Hash] Key data with access token and expiration
  def generate_ephemeral_key(ttl_minutes: DEFAULT_TTL_MINUTES)
    response = HTTParty.post(
      "#{DEEPGRAM_API_URL}/keys",
      headers: {
        "Authorization" => "Token #{deepgram_api_key}",
        "Content-Type" => "application/json"
      },
      body: {
        comment: "Voice session #{voice_session.session_id}",
        scopes: [ "usage:write" ], # Scope to streaming only
        time_to_live_in_seconds: ttl_minutes * 60,
        tags: [
          "voice_assistant",
          "entity:#{voice_session.entity_id}",
          "session:#{voice_session.session_id}"
        ]
      }.to_json
    )

    if response.success?
      key_data = response.parsed_response
      log_key_generation(key_data)
      {
        api_key: key_data["key"],
        key_id: key_data["api_key_id"],
        expires_at: Time.current + ttl_minutes.minutes,
        websocket_url: deepgram_websocket_url
      }
    else
      Rails.logger.error "Deepgram API error: #{response.code} - #{response.body}"
      raise "Failed to generate Deepgram API key: #{response.body}"
    end
  end

  # Build WebSocket configuration for Deepgram connection
  #
  # @param keywords [Array<String>] Keywords for boosting (contact names, etc.)
  # @param language [String] Language code (default: en-US)
  # @return [Hash] WebSocket configuration
  def websocket_config(keywords: [], language: nil)
    # Load settings from database with fallbacks to defaults
    config = {
      # Audio format - REQUIRED for raw PCM audio
      encoding: "linear16", # 16-bit PCM
      sample_rate: 16000, # Telephony quality (industry standard for voice, 66% less data than 48kHz)
      channels: 1,

      # Model & language
      model: DEFAULT_MODEL,
      language: language || DEFAULT_LANGUAGE,

      # Transcription features
      punctuate: true,
      interim_results: true,

      # Timing - optimized for responsiveness
      endpointing: 800, # ms of silence for end-of-turn (reduced for speed)
      utterance_end_ms: 1000, # Wait 1 second of silence before finalizing (much faster!)
      vad_events: true, # Voice activity detection events

      # Optional features
      filler_words: false,
      numerals: true
    }

    # Add keywords from voice session context (business terms, product names, contact names)
    session_keywords = voice_session.keywords
    all_keywords = (keywords + session_keywords).uniq.compact

    if all_keywords.any?
      config[:keywords] = all_keywords  # Boost recognition of important terms (up to 6x improvement)
    end

    config
  end

  # Validate webhook signature from Deepgram
  #
  # @param payload [String] Raw webhook payload
  # @param signature [String] X-Deepgram-Signature header value
  # @return [Boolean] True if signature is valid
  def self.validate_webhook_signature(payload, signature)
    return false if signature.blank?

    expected_signature = OpenSSL::HMAC.hexdigest(
      "SHA256",
      webhook_secret,
      payload
    )

    ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
  end

  # Parse Deepgram webhook payload
  #
  # @param payload [Hash] Webhook payload
  # @return [Hash] Parsed transcript data
  def self.parse_webhook(payload)
    {
      transcript: payload.dig("channel", "alternatives", 0, "transcript"),
      confidence: payload.dig("channel", "alternatives", 0, "confidence"),
      words: payload.dig("channel", "alternatives", 0, "words"),
      is_final: payload["is_final"],
      speech_final: payload["speech_final"],
      duration: payload["duration"],
      metadata: payload["metadata"]
    }
  end

  private

  def deepgram_api_key
    Rails.application.credentials.dig(:deepgram, :api_key) ||
      ENV["DEEPGRAM_API_KEY"] ||
      raise("Deepgram API key not configured")
  end

  def self.webhook_secret
    Rails.application.credentials.dig(:deepgram, :webhook_secret) ||
      ENV["DEEPGRAM_WEBHOOK_SECRET"] ||
      raise("Deepgram webhook secret not configured")
  end

  def deepgram_websocket_url
    "wss://api.deepgram.com/v1/listen"
  end

  def log_key_generation(key_data)
    Rails.logger.info({
      event: "deepgram_key_generated",
      session_id: voice_session.session_id,
      entity_id: voice_session.entity_id,
      key_id: key_data["api_key_id"],
      expires_at: Time.current + (key_data["time_to_live_in_seconds"] || 900).seconds
    }.to_json)
  end
end
