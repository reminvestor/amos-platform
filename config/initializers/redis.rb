# Configure Redis connection
require 'openssl'
uri = ENV["REDIS_URL"] || "redis://localhost:6379"

# Force use of http URI for Heroku
if uri.start_with?("rediss://")
  uri = uri.gsub("rediss://", "redis://")
end

# Configure Sidekiq with SSL verification disabled
Sidekiq.configure_server do |config|
  config.redis = { url: uri, ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE } }
end

Sidekiq.configure_client do |config|
  config.redis = { url: uri, ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE } }
end 