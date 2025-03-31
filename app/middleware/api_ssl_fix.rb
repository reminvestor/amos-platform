class ApiSslFix
  def initialize(app)
    @app = app
  end

  def call(env)
    # Special handling for API routes
    if env['PATH_INFO'] =~ /^\/api\//
      # Fix for Heroku's SSL termination
      env['HTTPS'] = 'on'
      env['HTTP_X_FORWARDED_SSL'] = 'on'
      env['HTTP_X_FORWARDED_PROTO'] = 'https'
      env['rack.url_scheme'] = 'https'
      
      # Log the request for debugging
      Rails.logger.info "API Request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
      Rails.logger.info "Headers: #{env.select { |k, v| k.start_with?('HTTP_') }.inspect}"
    end

    @app.call(env)
  rescue => e
    Rails.logger.error "ApiSslFix middleware error: #{e.message}\n#{e.backtrace.join("\n")}"
    # Return a proper JSON error for API routes
    if env['PATH_INFO'] =~ /^\/api\//
      [500, {'Content-Type' => 'application/json'}, [{ error: "Internal server error", message: e.message }.to_json]]
    else
      # Re-raise for non-API routes
      raise e
    end
  end
end 