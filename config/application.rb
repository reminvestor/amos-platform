require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module AgentMarketing
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks templates generators))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
    
    # Configure session store
    config.session_store :cookie_store, key: '_agent_marketing_session', domain: {
      production: ->(request) { request.domain },
      development: ->(request) { request.domain },
      test: ->(request) { request.domain }
    }.fetch(Rails.env.to_sym)

    # Add a special middleware to detect and log SSL issues
    config.middleware.insert_before 0, ->(app) {
      ->(*args) {
        env = args.first
        path = env["PATH_INFO"]
        
        # For API requests, add special SSL/https headers
        if path.start_with?('/api/')
          env["HTTPS"] = "on"
          env["HTTP_X_FORWARDED_PROTO"] = "https"
          env["rack.url_scheme"] = "https"
          
          begin
            return app.call(env)
          rescue Puma::HttpParserError => e
            # If we catch an SSL error on API, return a JSON response
            puts "API SSL Error: #{e.message}"
            [500, {"Content-Type" => "application/json"}, [{error: "API SSL Error: #{e.message}"}.to_json]]
          rescue => e
            # For any other error
            puts "API Error: #{e.message}"
            [500, {"Content-Type" => "application/json"}, [{error: "API Error: #{e.message}"}.to_json]]
          end
        else
          app.call(env)
        end
      }
    }
  end
end
