# Rack::Attack configuration for rate limiting and API protection
# https://github.com/rack/rack-attack

# Only configure if Rack::Attack is available (gem installed)
return unless defined?(Rack::Attack)

# Disable Rack::Attack in test environment
return if Rails.env.test?

class Rack::Attack
  ### Configure Cache ###

  # Use Redis for Rack::Attack (required for multi-container deployments)
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
  )

  ### Throttle Requests ###

  # Throttle Scout chat endpoint (AI requests are expensive)
  # Limit: 50 requests per minute per IP
  throttle("scout/ip", limit: 50, period: 1.minute) do |req|
    req.ip if req.path == "/scout/chat_stream" && req.post?
  end

  # Throttle Scout chat by user (for authenticated requests)
  # Limit: 100 requests per minute per user
  throttle("scout/user", limit: 100, period: 1.minute) do |req|
    if req.path == "/scout/chat_stream" && req.post?
      # Extract user ID from session
      req.env["rack.session"]&.dig("warden.user.user.key")&.first&.first
    end
  end

  # Throttle API v1 endpoints
  # Limit: 100 requests per minute per IP
  throttle("api/ip", limit: 100, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/v1/")
  end

  # Throttle API by API key (if implementing API keys in future)
  # Limit: 1000 requests per hour per API key
  throttle("api/key", limit: 1000, period: 1.hour) do |req|
    if req.path.start_with?("/api/v1/")
      req.env["HTTP_X_API_KEY"] # Extract API key from header
    end
  end

  # Throttle landing page submissions (prevent spam)
  # Limit: 10 submissions per hour per IP
  throttle("landing_page_submissions/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.path.match?(%r{^/api/v1/landing_page_submissions}) && req.post?
  end

  # Throttle login attempts (prevent brute force)
  # Limit: 5 attempts per 20 seconds per IP
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.ip
    end
  end

  # Throttle login attempts by email (prevent account-specific brute force)
  # Limit: 10 attempts per hour per email
  throttle("logins/email", limit: 10, period: 1.hour) do |req|
    if req.path == "/users/sign_in" && req.post?
      # Extract email from request params
      req.params["user"]&.dig("email")&.presence
    end
  end

  # API Login Rate Limiting (aggressive - prevent brute force on API)
  # Limit: 5 attempts per 15 minutes per email
  throttle('api/login/email', limit: 5, period: 15.minutes) do |req|
    if req.path == '/api/auth/login' && req.post?
      # Parse JSON body since req.params doesn't handle application/json
      email = if req.content_type&.include?('application/json') && req.body
                body = req.body.read
                req.body.rewind
                (JSON.parse(body) rescue {})['email']
              else
                req.params['email']
              end
      email&.to_s&.downcase&.strip.presence
    end
  end

  # API Login Rate Limiting by IP
  # Limit: 10 attempts per 15 minutes per IP
  throttle('api/login/ip', limit: 10, period: 15.minutes) do |req|
    if req.path == '/api/auth/login' && req.post?
      req.ip
    end
  end

  # API Registration Rate Limiting
  # Limit: 3 registrations per hour per IP
  throttle('api/register/ip', limit: 3, period: 1.hour) do |req|
    if req.path == '/api/auth/register' && req.post?
      req.ip
    end
  end

  # API Key Usage Rate Limiting
  # Limit: 300 requests per 5 minutes per API key
  throttle('api/authenticated/token', limit: 300, period: 5.minutes) do |req|
    if req.env['HTTP_AUTHORIZATION'].present?
      token = req.env['HTTP_AUTHORIZATION'].gsub(/^Bearer /, '')
      "api_key:#{Digest::SHA256.hexdigest(token)}" if token.present?
    end
  end

  ### Block Requests ###

  # Block suspicious requests from known bad actors
  # This list can be populated from security monitoring services
  blocklist("block bad IPs") do |req|
    # Example: Block specific IPs (replace with actual bad IPs)
    # [ "1.2.3.4", "5.6.7.8" ].include?(req.ip)
    false # Disabled by default
  end

  # Block requests with suspicious user agents (bots, scrapers)
  blocklist("block bad user agents") do |req|
    # Block requests without user agent or with suspicious patterns
    user_agent = req.user_agent.to_s.downcase
    user_agent.blank? ||
      user_agent.include?("scrapy") ||
      user_agent.include?("crawler") ||
      user_agent.include?("bot") && !user_agent.include?("googlebot")
  end

  ### Custom Responses ###

  # Customize response for throttled requests
  self.throttled_responder = lambda do |request|
    match_data = request.env['rack.attack.match_data'] || {}
    retry_after = match_data[:period] || 60
    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s
      },
      [{ error: 'Rate limit exceeded. Please try again later.' }.to_json]
    ]
  end

  # Customize response for blocked requests
  self.blocklisted_responder = lambda do |_env|
    [
      403, # Forbidden
      { "Content-Type" => "application/json" },
      [ { error: "Forbidden", message: "Your request has been blocked." }.to_json ]
    ]
  end

  ### Logging ###

  # Log blocked and throttled requests
  ActiveSupport::Notifications.subscribe("rack.attack") do |_name, _start, _finish, _request_id, payload|
    req = payload[:request]
    case req.env["rack.attack.match_type"]
    when :throttle
      Rails.logger.warn "[Rack::Attack] Throttled: #{req.ip} - #{req.path}"
    when :blocklist
      Rails.logger.warn "[Rack::Attack] Blocked: #{req.ip} - #{req.path}"
    end
  end
end
