# frozen_string_literal: true

# lib/middleware/cors_middleware.rb
# Simple CORS middleware for mobile app development
# Note: Namespaced as Middleware::CorsMiddleware to match Zeitwerk autoloading expectations
module Middleware
  class CorsMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      origin = env['HTTP_ORIGIN']

      # Allow localhost and 127.0.0.1 on any port
      if origin && origin =~ %r{\Ahttp://(localhost|127\.0\.0\.1):\d+\z}
        # Handle preflight OPTIONS request
        if env['REQUEST_METHOD'] == 'OPTIONS'
          return [
            200,
            cors_headers(origin),
            ['']
          ]
        end

        # Process the request normally and add CORS headers to response
        status, headers, response = @app.call(env)
        headers.merge!(cors_headers(origin))
        [status, headers, response]
      else
        # No CORS origin, process normally
        @app.call(env)
      end
    end

    private

    def cors_headers(origin)
      {
        'Access-Control-Allow-Origin' => origin,
        'Access-Control-Allow-Methods' => 'GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD',
        'Access-Control-Allow-Headers' => 'Content-Type, Accept, Authorization, X-Requested-With, X-CSRF-Token',
        'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Expose-Headers' => 'Authorization',
        'Access-Control-Max-Age' => '1728000'
      }
    end
  end
end

