# Configure which AI service to use based on environment
Rails.application.config.after_initialize do
  # Determine which AI service to use
  ai_provider = ENV['AI_PROVIDER'] || (Rails.env.production? ? 'bedrock' : 'openai')
  
  Rails.logger.info "🤖 AI Provider: #{ai_provider}"
  
  # Set up the appropriate service
  case ai_provider
  when 'bedrock'
    # Use AWS Bedrock for all AI services
    Rails.application.config.ai_service = :bedrock
    Rails.application.config.ai_service_class = BedrockService
  when 'claude'
    # Use Claude API directly
    Rails.application.config.ai_service = :claude
    Rails.application.config.ai_service_class = ClaudeService
  when 'openai'
    # Use OpenAI API
    Rails.application.config.ai_service = :openai
    Rails.application.config.ai_service_class = OpenaiService
  else
    Rails.logger.warn "Unknown AI provider: #{ai_provider}, defaulting to OpenAI"
    Rails.application.config.ai_service = :openai
    Rails.application.config.ai_service_class = OpenaiService
  end
end

# Helper method to get the configured AI service
module AiServiceHelper
  def self.get_service
    service_class = Rails.application.config.ai_service_class || OpenaiService
    service_class.new
  end
end
