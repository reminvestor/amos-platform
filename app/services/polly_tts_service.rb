require 'aws-sdk-polly'
require 'aws-sdk-sts'

class PollyTtsService
  CACHE_TTL = 14.minutes # Just under the 15-minute STS limit
  
  # Available neural voices
  VOICES = {
    'Matthew' => { engine: 'neural', language_code: 'en-US', gender: 'Male' },
    'Joanna' => { engine: 'neural', language_code: 'en-US', gender: 'Female' },
    'Amy' => { engine: 'neural', language_code: 'en-GB', gender: 'Female' },
    'Brian' => { engine: 'neural', language_code: 'en-GB', gender: 'Male' },
    'Camila' => { engine: 'neural', language_code: 'pt-BR', gender: 'Female' },
    'Lupe' => { engine: 'neural', language_code: 'es-US', gender: 'Female' },
    'Takumi' => { engine: 'neural', language_code: 'ja-JP', gender: 'Male' }
  }.freeze

  class << self
    # Get or create Polly client (not cached due to serialization issues)
    def polly_client
      # Use the same AWS credentials as the rest of the app
      # No special role needed - just ensure IAM user/role has polly:SynthesizeSpeech permission
      region = ENV['AWS_REGION'] || 'us-east-1'
      Rails.logger.info "🔧 Creating Polly client for region: #{region}"
      
      # Check if AWS credentials are available
      if ENV['AWS_ACCESS_KEY_ID'].present?
        Rails.logger.info "✅ AWS credentials found in ENV"
      else
        Rails.logger.info "⚠️ No AWS_ACCESS_KEY_ID in ENV, will try other credential sources"
      end
      
      Aws::Polly::Client.new(
        region: region
        # AWS SDK will automatically use credentials from:
        # 1. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
        # 2. EC2/ECS instance profile
        # 3. ~/.aws/credentials file
      )
    rescue => e
      Rails.logger.error "❌ Failed to create Polly client: #{e.message}"
      raise
    end

    # Pre-warm the cache on application boot
    def warm_cache
      Thread.new do
        Rails.logger.info "🔥 Pre-warming Polly client..."
        polly_client
        Rails.logger.info "✅ Polly client ready"
      rescue => e
        Rails.logger.error "Failed to initialize Polly client: #{e.message}"
      end
    end
  end

  def initialize(voice_id: 'Matthew', engine: nil)
    @voice_id = voice_id
    @voice_config = VOICES[voice_id] || VOICES['Matthew']
    @engine = engine || @voice_config[:engine]
    @client = self.class.polly_client
  end

  # Synthesize text to speech with streaming
  def synthesize_stream(text, include_speech_marks: true)
    return { success: false, error: "Text is too long (max 3000 chars)" } if text.length > 3000
    return { success: false, error: "Text is empty" } if text.blank?

    # Clean the text for better pronunciation
    cleaned_text = prepare_text(text)

    begin
      Rails.logger.info "🎤 TTS: Synthesizing #{text.length} chars with voice #{@voice_id}"
      
      # Generate speech audio
      audio_response = @client.synthesize_speech({
        engine: @engine,
        language_code: @voice_config[:language_code],
        output_format: 'mp3',
        sample_rate: '24000',
        text: cleaned_text,
        text_type: 'ssml',
        voice_id: @voice_id
      })

      # Generate speech marks if requested (for word-level timing)
      speech_marks = nil
      if include_speech_marks
        marks_response = @client.synthesize_speech({
          engine: @engine,
          language_code: @voice_config[:language_code],
          output_format: 'json',
          speech_mark_types: ['word', 'sentence'],
          text: cleaned_text,
          text_type: 'ssml',
          voice_id: @voice_id
        })
        
        # Parse speech marks
        speech_marks = parse_speech_marks(marks_response.audio_stream)
      end

      {
        success: true,
        audio_stream: audio_response.audio_stream,
        content_type: 'audio/mpeg',
        speech_marks: speech_marks,
        metadata: {
          voice_id: @voice_id,
          engine: @engine,
          language: @voice_config[:language_code],
          characters: text.length
        }
      }
    rescue Aws::Polly::Errors::ServiceError => e
      Rails.logger.error "❌ Polly synthesis failed: #{e.message}"
      Rails.logger.error "   Error class: #{e.class.name}"
      Rails.logger.error "   Error code: #{e.code}" if e.respond_to?(:code)
      Rails.logger.error "   Status code: #{e.http_status}" if e.respond_to?(:http_status)
      { success: false, error: "Polly error: #{e.message}" }
    rescue => e
      Rails.logger.error "❌ Unexpected TTS error: #{e.class.name} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      { success: false, error: "TTS error: #{e.message}" }
    end
  end

  # Get presigned URL for client-side synthesis (alternative approach)
  def generate_presigned_url(text, expires_in: 60)
    request = {
      engine: @engine,
      language_code: @voice_config[:language_code],
      output_format: 'mp3',
      text: prepare_text(text),
      text_type: 'ssml',
      voice_id: @voice_id
    }

    signer = Aws::Polly::Presigner.new(client: @client)
    signer.synthesize_speech_presigned_url(request, expires_in: expires_in)
  rescue => e
    Rails.logger.error "Failed to generate presigned URL: #{e.message}"
    nil
  end

  private

  def prepare_text(text)
    # First remove emojis and clean the text
    cleaned_text = remove_emojis(text)
    
    # Remove markdown formatting for cleaner speech
    cleaned_text = cleaned_text
      .gsub(/\*{1,2}([^*]+)\*{1,2}/, '\1') # Remove bold/italic
      .gsub(/`([^`]+)`/, '\1') # Remove inline code formatting
      .gsub(/^#+\s+/, '') # Remove heading markers
      .gsub(/^[-*]\s+/, '') # Remove list markers
      .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1') # Convert links to just text
    
    # Wrap in SSML for better control
    ssml = "<speak>"
    
    # Convert markdown bold to emphasis (if any remain)
    cleaned_text = cleaned_text.gsub(/\*\*(.*?)\*\*/, '<emphasis level="moderate">\1</emphasis>')
    
    # Add pauses for better rhythm
    cleaned_text = cleaned_text.gsub(/\. /, '. <break time="300ms"/> ')
    cleaned_text = cleaned_text.gsub(/\? /, '? <break time="300ms"/> ')
    cleaned_text = cleaned_text.gsub(/! /, '! <break time="300ms"/> ')
    cleaned_text = cleaned_text.gsub(/: /, ': <break time="200ms"/> ')
    
    # Handle common abbreviations
    cleaned_text = cleaned_text.gsub(/\bAI\b/, '<sub alias="A.I.">AI</sub>')
    cleaned_text = cleaned_text.gsub(/\bAPI\b/, '<sub alias="A.P.I.">API</sub>')
    cleaned_text = cleaned_text.gsub(/\bURL\b/, '<sub alias="U.R.L.">URL</sub>')
    
    ssml + cleaned_text + "</speak>"
  end
  
  # Remove emojis and other non-speech Unicode characters
  def remove_emojis(text)
    # Remove common emoji ranges
    text.gsub(/[\u{1F600}-\u{1F64F}]/, '') # Emoticons
        .gsub(/[\u{1F300}-\u{1F5FF}]/, '') # Misc Symbols and Pictographs
        .gsub(/[\u{1F680}-\u{1F6FF}]/, '') # Transport and Map
        .gsub(/[\u{1F1E0}-\u{1F1FF}]/, '') # Regional country flags
        .gsub(/[\u{2600}-\u{26FF}]/, '')   # Misc symbols
        .gsub(/[\u{2700}-\u{27BF}]/, '')   # Dingbats
        .gsub(/[\u{1F900}-\u{1F9FF}]/, '') # Supplemental Symbols and Pictographs
        .gsub(/[\u{1FA70}-\u{1FAFF}]/, '') # Symbols and Pictographs Extended-A
        .gsub(/[\u{1F700}-\u{1F77F}]/, '') # Alchemical Symbols
        .gsub(/[\u{1F780}-\u{1F7FF}]/, '') # Geometric Shapes Extended
        .gsub(/[\u{1F800}-\u{1F8FF}]/, '') # Supplemental Arrows-C
        .strip
  end

  def parse_speech_marks(stream)
    marks = []
    stream.each_line do |line|
      mark = JSON.parse(line)
      marks << {
        time: mark['time'],
        type: mark['type'],
        value: mark['value'],
        start: mark['start'],
        end: mark['end']
      }
    end
    marks
  rescue => e
    Rails.logger.error "Failed to parse speech marks: #{e.message}"
    []
  end

  # Get list of available voices for a language
  def self.available_voices(language_code: 'en-US')
    client = polly_client
    response = client.describe_voices({
      language_code: language_code,
      include_additional_language_codes: true
    })
    
    response.voices.map do |voice|
      {
        id: voice.id,
        name: voice.name,
        gender: voice.gender,
        language_code: voice.language_code,
        language_name: voice.language_name,
        neural: voice.supported_engines.include?('neural')
      }
    end
  rescue => e
    Rails.logger.error "Failed to get voices: #{e.message}"
    []
  end
end
