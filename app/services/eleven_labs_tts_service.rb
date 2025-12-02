require 'net/http'
require 'uri'
require 'json'

class ElevenLabsTtsService
  # Default settings
  DEFAULT_MODEL = "eleven_turbo_v2_5" # Low latency model
  DEFAULT_VOICE_ID = "JBFqnCBsd6RMkjVDRZzb" # George (British, warm) - typical default, or we can pick another
  
  # Common voices mapping for easy reference
  # These are public Eleven Labs voices
  VOICES = {
    'Rachel' => { voice_id: '21m00Tcm4TlvDq8ikWAM', gender: 'Female', description: 'American, calm' },
    'Drew' => { voice_id: '29vD33N1CtxCmqQRPOHJ', gender: 'Male', description: 'American, news' },
    'Clyde' => { voice_id: '2EiwWnXFnvU5JabPnv8n', gender: 'Male', description: 'American, deep' },
    'Mimi' => { voice_id: 'LrHWlFk9Nhvxvi53045r', gender: 'Female', description: 'Australian, child' },
    'Fin' => { voice_id: 'D38z5RcWu1voky8WS1ja', gender: 'Male', description: 'Irish, energetic' },
    'Nicole' => { voice_id: 'piTKgcLEGmPE4e6mEKli', gender: 'Female', description: 'American, whisper' },
    'George' => { voice_id: 'JBFqnCBsd6RMkjVDRZzb', gender: 'Male', description: 'British, warm' },
    'Emily' => { voice_id: 'LcfcDJNUP1GQjkzn1xUU', gender: 'Female', description: 'American, calm' },
    'Charlie' => { voice_id: 'IKne3meq5aSn9XLyUdCD', gender: 'Male', description: 'Australian, casual' }
  }.freeze

  def initialize(voice_id: nil, model_id: nil)
    @voice_id = resolve_voice_id(voice_id) || DEFAULT_VOICE_ID
    @model_id = model_id || DEFAULT_MODEL
    @api_key = fetch_api_key
  end

  # Synthesize text to speech with streaming
  # Matches interface of PollyTtsService
  def synthesize_stream(text, include_speech_marks: false)
    return { success: false, error: "Text is too long (max 5000 chars)" } if text.length > 5000
    return { success: false, error: "Text is empty" } if text.blank?

    # Eleven Labs doesn't support speech marks in the same way as Polly in the basic TTS API
    # We'll ignore include_speech_marks for now or implement if needed via timestamps feature
    
    begin
      Rails.logger.info "🎤 ElevenLabs TTS: Synthesizing #{text.length} chars with voice #{@voice_id}"
      
      uri = URI("https://api.elevenlabs.io/v1/text-to-speech/#{@voice_id}/stream")
      uri.query = URI.encode_www_form({ optimize_streaming_latency: 4 }) # Max optimization
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30 # seconds

      request = Net::HTTP::Post.new(uri)
      request['xi-api-key'] = @api_key
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'audio/mpeg'
      
      payload = {
        text: text,
        model_id: @model_id,
        voice_settings: {
          stability: 0.5,
          similarity_boost: 0.75,
          style: 0.0,
          use_speaker_boost: true
        }
      }
      
      request.body = payload.to_json

      response = http.request(request)

      if response.code.to_i == 200
        # Create a StringIO like object for consistency with Polly
        audio_stream = StringIO.new(response.body)
        
        {
          success: true,
          audio_stream: audio_stream,
          content_type: 'audio/mpeg',
          speech_marks: nil, # Not supported in standard stream yet
          metadata: {
            voice_id: @voice_id,
            provider: 'eleven_labs',
            model: @model_id,
            characters: text.length
          }
        }
      else
        Rails.logger.error "❌ ElevenLabs TTS failed: #{response.code} - #{response.body}"
        { success: false, error: "ElevenLabs error: #{response.message}" }
      end
    rescue => e
      Rails.logger.error "❌ Unexpected TTS error: #{e.class.name} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      { success: false, error: "TTS error: #{e.message}" }
    end
  end

  def self.available_voices(language_code: 'en-US')
    # Map our static constant to the expected format
    VOICES.map do |name, data|
      {
        id: name, # Use name as ID for internal reference, we map back to voice_id in initialize
        name: name,
        gender: data[:gender],
        language_code: 'en-US', # Eleven Labs v2 models are multilingual but we default to en-US context
        engine: 'neural',
        provider: 'eleven_labs'
      }
    end
  end

  private

  def resolve_voice_id(id)
    return nil if id.blank?
    # Check if it's one of our friendly names
    if VOICES.key?(id)
      VOICES[id][:voice_id]
    else
      # Assume it's a raw Eleven Labs voice ID
      id
    end
  end

  def fetch_api_key
    # Priority: ENV -> Rails Credentials
    ENV["ELEVEN_LABS_API_KEY"] || Rails.application.credentials.dig(:eleven_labs, :api_key)
  end
end

