# Pinecone configuration
require 'pinecone'

Rails.application.config.to_prepare do
  if ENV['PINECONE_API_KEY'].present? && ENV['PINECONE_ENVIRONMENT'].present?
    Pinecone.configure do |config|
      config.api_key = ENV['PINECONE_API_KEY']
      config.environment = ENV['PINECONE_ENVIRONMENT']
    end
    
    Rails.logger.info "✅ Pinecone configured for environment: #{ENV['PINECONE_ENVIRONMENT']}"
  else
    Rails.logger.warn "⚠️ Pinecone not configured - missing PINECONE_API_KEY or PINECONE_ENVIRONMENT"
  end
end
