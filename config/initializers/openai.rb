# OpenAI API Configuration
require 'openai'

# Set default timeout for OpenAI requests
OpenAI.configure do |config|
  # Default timeout is 120 seconds
  config.request_timeout = 240
  
  # Logging is handled automatically in development
end

# Check if API key is set
unless ENV['OPENAI_API_KEY'].present?
  Rails.logger.warn "WARNING: OPENAI_API_KEY environment variable is not set. AI features will not work."
end 