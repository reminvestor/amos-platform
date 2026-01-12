# frozen_string_literal: true

# lib/middleware/cors_middleware.rb
# CORS middleware for mobile app development and landing page subdomains
# Note: Namespaced as Middleware::CorsMiddleware to match Zeitwerk autoloading expectations
module Middleware
  class CorsMiddleware
    # Landing page subdomain pattern: https://*.lp.amoslabs.com
    LANDING_PAGE_ORIGIN_PATTERN = %r{\Ahttps://[a-z0-9\-]+\.lp\.[a-z0-9\-]+\.[a-z]+\z}i.freeze

    # Development localhost pattern
    LOCALHOST_ORIGIN_PATTERN = %r{\Ahttp://(localhost|127\.0\.0\.1):\d+\z}.freeze

    # Local development landing pages: http://*.lp.lvh.me:3000
    LOCAL_LANDING_PAGE_PATTERN = %r{\Ahttp://[a-z0-9\-]+\.lp\.lvh\.me:\d+\z}i.freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      origin = env["HTTP_ORIGIN"]

      # Check if origin is allowed
      if origin && allowed_origin?(origin)
        # Handle preflight OPTIONS request
        if env["REQUEST_METHOD"] == "OPTIONS"
          return [
            200,
            cors_headers(origin),
            [""]
          ]
        end

        # Process the request normally and add CORS headers to response
        status, headers, response = @app.call(env)
        headers.merge!(cors_headers(origin))
        [status, headers, response]
      else
        # No CORS origin or not allowed, process normally
        @app.call(env)
      end
    end

    private

    def allowed_origin?(origin)
      # Allow localhost for development
      return true if origin =~ LOCALHOST_ORIGIN_PATTERN

      # Allow landing page subdomains (production)
      return true if origin =~ LANDING_PAGE_ORIGIN_PATTERN

      # Allow local landing page subdomains (development with lvh.me)
      return true if origin =~ LOCAL_LANDING_PAGE_PATTERN

      false
    end

    def cors_headers(origin)
      {
        "Access-Control-Allow-Origin" => origin,
        "Access-Control-Allow-Methods" => "GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD",
        "Access-Control-Allow-Headers" => "Content-Type, Accept, Authorization, X-Requested-With, X-CSRF-Token",
        "Access-Control-Allow-Credentials" => "true",
        "Access-Control-Expose-Headers" => "Authorization",
        "Access-Control-Max-Age" => "1728000"
      }
    end
  end
end

