class Api::TtsController < ApplicationController
  before_action :authenticate_user!
  
  # POST /api/tts/synthesize
  # Stream synthesized audio back to client
  def synthesize
    text = params[:text]
    
    # Get user's voice preferences
    prefs = current_user.tts_preferences || {}
    
    # Default to Eleven Labs 'George' if not set
    provider = params[:provider] || prefs['provider']
    
    # If provider is not explicitly set, try to infer from voice_id
    if provider.blank?
      requested_voice_id = params[:voice_id] || prefs['voice_id']
      
      # Check if it's a known Polly voice
      is_polly_voice = PollyTtsService::VOICES.key?(requested_voice_id) || 
                       ['Matthew', 'Joanna', 'Ivy', 'Kendra', 'Kimberly', 'Salli', 'Joey', 'Justin', 'Kevin', 'Ruth', 'Stephen', 'Olivia'].include?(requested_voice_id)
      
      provider = is_polly_voice ? 'polly' : 'eleven_labs'
    else
      # EVEN IF provider is set (e.g. to 'eleven_labs' by default), check for mismatch
      # This handles legacy clients/settings where provider=eleven_labs but voice_id=Joanna
      requested_voice_id = params[:voice_id] || prefs['voice_id']
      is_polly_voice = PollyTtsService::VOICES.key?(requested_voice_id) || 
                       ['Matthew', 'Joanna', 'Ivy', 'Kendra', 'Kimberly', 'Salli', 'Joey', 'Justin', 'Kevin', 'Ruth', 'Stephen', 'Olivia'].include?(requested_voice_id)
      
      if is_polly_voice && provider == 'eleven_labs'
        Rails.logger.info "⚠️ Provider mismatch detected: #{provider} requested but voice is #{requested_voice_id} (Polly). Forcing Polly."
        provider = 'polly'
      end
    end
    
    if provider == 'eleven_labs'
      voice_id = params[:voice_id] || prefs['eleven_labs_voice_id'] || 'George'
      # No engine param for Eleven Labs in this context, but we pass it if present
      engine = nil 
    else
      # Fallback to Polly
      voice_id = params[:voice_id] || prefs['voice_id'] || 'Matthew'
      engine = prefs['engine'] || 'neural'
    end
    
    # Validate input
    if text.blank?
      return render json: { error: 'Text is required' }, status: :bad_request
    end
    
    if text.length > 5000
      return render json: { error: 'Text too long (max 5000 characters)' }, status: :bad_request
    end
    
    # Initialize TTS service with user preferences
    tts_service = if provider == 'eleven_labs'
                    ElevenLabsTtsService.new(voice_id: voice_id)
                  else
                    PollyTtsService.new(voice_id: voice_id, engine: engine)
                  end
    
    # Synthesize with streaming
    result = tts_service.synthesize_stream(text, include_speech_marks: params[:speech_marks] != 'false')
    
    if result[:success]
      # Log usage for analytics
      log_tts_usage(text.length, voice_id)
      
      # Send the audio data as a binary response
      response.headers['Content-Type'] = result[:content_type]
      response.headers['Cache-Control'] = 'no-cache'
      
      # Include speech marks as a header if requested
      if result[:speech_marks]
        response.headers['X-Speech-Marks'] = Base64.strict_encode64(result[:speech_marks].to_json).gsub("\n", "")
      end
      
      # Send the binary audio data
      # Read the entire stream into memory first
      audio_data = result[:audio_stream].read
      result[:audio_stream].rewind if result[:audio_stream].respond_to?(:rewind)
      
      send_data audio_data, 
                type: result[:content_type], 
                disposition: 'inline',
                status: :ok
    else
      render json: { error: result[:error] }, status: :service_unavailable
    end
  end
  
  # GET /api/tts/voices
  # Get available voices for user's language
  def voices
    language_code = params[:language] || 'en-US'
    provider = params[:provider] || 'eleven_labs' # Default to Eleven Labs
    
    voices = if provider == 'eleven_labs'
               Rails.cache.fetch("eleven_labs_voices", expires_in: 1.day) do
                 ElevenLabsTtsService.available_voices
               end
             else
               Rails.cache.fetch("polly_voices_#{language_code}", expires_in: 1.day) do
                 PollyTtsService.available_voices(language_code: language_code)
               end
             end
    
    render json: { voices: voices }
  end
  
  # POST /api/tts/presigned_url
  # Alternative: Get presigned URL for client-side synthesis
  def presigned_url
    text = params[:text]
    voice_id = params[:voice_id] || 'Matthew'
    
    if text.blank? || text.length > 3000
      return render json: { error: 'Invalid text' }, status: :bad_request
    end
    
    tts_service = PollyTtsService.new(voice_id: voice_id)
    url = tts_service.generate_presigned_url(text, expires_in: 300) # 5 minutes
    
    if url
      render json: { url: url, expires_in: 300 }
    else
      render json: { error: 'Failed to generate URL' }, status: :service_unavailable
    end
  end
  
  # GET /api/tts/preferences
  # Get user's TTS preferences
  def preferences
    render json: { preferences: current_user.tts_preferences || {} }
  end
  
  # PATCH /api/tts/preferences
  # Update user's TTS preferences
  def update_preferences
    # Parse boolean values correctly
    preferences = current_user.tts_preferences || {}
    
    if params.has_key?(:enabled)
      preferences['enabled'] = [true, 'true', 1, '1'].include?(params[:enabled])
    end
    
    preferences['provider'] = params[:provider] if params[:provider].present?
    
    # Handle provider-specific voice IDs
    if preferences['provider'] == 'eleven_labs'
      preferences['eleven_labs_voice_id'] = params[:voice_id] if params[:voice_id].present?
    else
      preferences['voice_id'] = params[:voice_id] if params[:voice_id].present?
    end
    
    preferences['engine'] = params[:engine] if params[:engine].present?
    preferences['speed'] = params[:speed].to_f if params[:speed].present?
    preferences['volume'] = params[:volume].to_f if params[:volume].present?
    
    current_user.update!(tts_preferences: preferences)
    render json: { preferences: current_user.tts_preferences }
  end
  
  # GET /api/tts/test
  # Test TTS configuration and AWS connection
  def test
    begin
      # Test creating Polly client
      tts_service = PollyTtsService.new(voice_id: 'Matthew')
      
      # Test with simple text
      result = tts_service.synthesize_stream("Test", include_speech_marks: false)
      
      if result[:success]
        render json: { 
          status: 'ok',
          message: 'TTS is working',
          aws_region: ENV['AWS_REGION'] || 'us-east-1',
          credentials_present: ENV['AWS_ACCESS_KEY_ID'].present?
        }
      else
        render json: { 
          status: 'error',
          message: 'TTS synthesis failed',
          error: result[:error],
          aws_region: ENV['AWS_REGION'] || 'us-east-1',
          credentials_present: ENV['AWS_ACCESS_KEY_ID'].present?
        }, status: :service_unavailable
      end
    rescue => e
      render json: { 
        status: 'error',
        message: 'TTS test failed',
        error: e.message,
        error_class: e.class.name,
        aws_region: ENV['AWS_REGION'] || 'us-east-1',
        credentials_present: ENV['AWS_ACCESS_KEY_ID'].present?
      }, status: :internal_server_error
    end
  end

  private
  
  def user_voice_preference
    current_user.tts_preferences&.dig('voice_id')
  end
  
  def log_tts_usage(character_count, voice_id)
    TtsUsageLog.create!(
      user: current_user,
      entity: current_entity,
      character_count: character_count,
      voice_id: voice_id,
      cost_cents: calculate_tts_cost(character_count)
    ) rescue nil
  end
  
  def calculate_tts_cost(character_count)
    # AWS Polly Neural: $16 per 1M characters
    (character_count * 0.0016).round(2)
  end
end
