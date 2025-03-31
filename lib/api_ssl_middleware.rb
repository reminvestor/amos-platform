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
      
      begin
        @app.call(env)
      rescue Puma::HttpParserError => e
        # If we catch an SSL error on API, return a JSON response
        Rails.logger.error("API SSL Error: #{e.message}")
        [500, {"Content-Type" => "application/json"}, [{error: "API SSL Error: #{e.message}"}.to_json]]
      rescue => e
        # For any other error
        Rails.logger.error("API Error: #{e.message}")
        [500, {"Content-Type" => "application/json"}, [{error: "API Error: #{e.message}"}.to_json]]
      end
    else
      @app.call(env)
    end
  end
end 