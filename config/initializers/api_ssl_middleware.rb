# Define the middleware class here to avoid loading issues
class ApiSslMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    path = env["PATH_INFO"]
    
    # For API requests, add special SSL/https headers
    if path.start_with?('/api/')
      env["HTTPS"] = "on"
      env["HTTP_X_FORWARDED_PROTO"] = "https"
      env["rack.url_scheme"] = "https"
    end
    
    @app.call(env)
  rescue => e
    # Log any errors
    if defined?(Rails) && Rails.logger
      Rails.logger.error("API Middleware Error: #{e.class.name} - #{e.message}")
    end
    
    # Return a JSON error response
    [500, {"Content-Type" => "application/json"}, ['{"error":"Internal Server Error"}']]
  end
end

# Add our API SSL middleware
Rails.application.config.middleware.use ApiSslMiddleware 