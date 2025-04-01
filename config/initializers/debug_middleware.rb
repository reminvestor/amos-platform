# Define a debugging middleware to inspect and log request details
class RequestDebugMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    # Log key info about the request
    if defined?(Rails) && Rails.logger
      # Get request info
      protocol = env["rack.url_scheme"] || "unknown"
      ssl = env["HTTPS"] == "on" ? "yes" : "no"
      forwarded_proto = env["HTTP_X_FORWARDED_PROTO"] || "none"
      path = env["PATH_INFO"] || "unknown"
      
      # Log it
      Rails.logger.info("DEBUG REQUEST: protocol=#{protocol}, ssl=#{ssl}, " +
                       "forwarded_proto=#{forwarded_proto}, path=#{path}")
      
      # Log all headers
      headers = env.select { |k, v| k.start_with?('HTTP_') }
      Rails.logger.info("REQUEST HEADERS: #{headers.inspect}")
    end
    
    # Continue with the request
    @app.call(env)
  end
end

# Insert at the very beginning of the middleware stack
Rails.application.config.middleware.insert_before 0, RequestDebugMiddleware 