# Configure AWS Polly TTS
Rails.application.config.after_initialize do
  if Rails.env.production?
    # Pre-warm Polly client on application boot
    # This eliminates delays on first TTS request
    PollyTtsService.warm_cache
  end
end

# TTS configuration
Rails.application.config.tts = {
  # System defaults (users can override in their preferences)
  default_voice: 'Matthew',
  default_engine: 'neural',
  
  # Feature flags
  enabled_by_default: true,
  
  # Performance settings
  max_text_length: 3000,
  cache_ttl: 14.minutes,
  
  # Cost control
  daily_character_limit_per_user: 100_000 # ~$1.60/day max per user
}
