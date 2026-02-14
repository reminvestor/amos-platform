require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "active_storage/engine"
require "action_text/engine"
# require "sprockets/railtie" # Not using Sprockets
# Ensure Propshaft is loaded before its railtie to avoid NameError on some setups
require "propshaft"
require "propshaft/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Require propshaft railtie after gems are loaded
require "propshaft/railtie"

module AmosLabs
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Use Propshaft as the asset pipeline
    config.assets.enabled = true

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks templates generators scripts])

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
    # Use Redis-backed cache store in production to avoid 4KB cookie limit
    # Use cookie store in development/test for simplicity
    if Rails.env.production?
      config.session_store :cache_store, 
        key: "_amos_labs_session",
        expire_after: 1.week,
        domain: :all
    else
      config.session_store :cookie_store, 
        key: "_amos_labs_session",
        domain: :all
    end

    # Load custom middleware path
    config.autoload_paths << Rails.root.join("lib")
    config.eager_load_paths << Rails.root.join("lib")

    # Configure Zeitwerk inflections for Amos AI acronym
    Rails.autoloaders.main.inflector.inflect("amos_ai" => "AmosAI")

    # Set Solid::Queue as the queue adapter
    config.active_job.queue_adapter = :solid_queue

    # Enable Rack::Attack middleware for rate limiting (if gem is installed)
    config.middleware.use Rack::Attack if defined?(Rack::Attack)

    # CORS middleware for mobile apps and local development
    require_relative '../lib/middleware/cors_middleware'
    config.middleware.insert_before 0, Middleware::CorsMiddleware

    # Subdomain router for landing page subdomain support
    # Routes *.lp.{domain} requests to the LpController
    require_relative '../lib/middleware/subdomain_router'
    config.middleware.insert_after Middleware::CorsMiddleware, Middleware::SubdomainRouter

  end
end
