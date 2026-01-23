require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on Amazon S3 (see config/storage.yml for options).
  config.active_storage.service = :amazon

  # Set Active Storage URL host in production
  # Use maximum expiration (1 year) to prevent landing page images from expiring
  config.active_storage.service_urls_expire_in = 1.year
  Rails.application.routes.default_url_options[:host] = ENV["APP_HOST"] || "app.amoslabs.com"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # IMPORTANT: On Heroku, force_ssl must be false as Heroku handles SSL termination
  # However, we still enforce HSTS and secure cookies
  config.force_ssl = false

  # Enforce HSTS (HTTP Strict Transport Security) headers
  # This tells browsers to always use HTTPS for future requests
  config.ssl_options = {
    hsts: {
      expires: 1.year,
      subdomains: true,
      preload: true
    }
  }

  # Configure proxy settings for Heroku
  config.action_dispatch.trusted_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES +
    [ IPAddr.new("10.0.0.0/8"), IPAddr.new("172.16.0.0/12"), IPAddr.new("192.168.0.0/16") ]

  # Add Heroku's proxy IPs as trusted
  config.action_dispatch.ip_spoofing_check = false

  # Disable forgery protection for API routes
  config.action_controller.allow_forgery_protection = false

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "debug")

  # Force Rails to log to STDOUT for Heroku visibility
  config.logger = ActiveSupport::Logger.new(STDOUT)
  config.logger.level = Logger::DEBUG

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :solid_cache_store
  
  # Use Redis for caching to share data between web and worker processes
  config.cache_store = :redis_cache_store, { 
    url: ENV["REDIS_URL"] || ENV["ELASTICACHE_REDIS_URL"],
    namespace: "amos_prod_cache",
    expires_in: 90.minutes,
    connect_timeout: 3,
    read_timeout: 1,
    write_timeout: 1,
    reconnect_attempts: 1,
    error_handler: -> (method:, returning:, exception:) {
      Rails.logger.error "[Redis Cache Error] #{method} failed: #{exception.class} - #{exception.message}"
      nil # Return nil on errors to prevent crashes
    }
  }

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :primary } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  config.action_mailer.raise_delivery_errors = true

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = {
    host: ENV["APPLICATION_HOST"] || "app.amoslabs.com",
    protocol: "https"
  }

  # Set up asset host for emails (used for images)
  config.action_mailer.asset_host = "https://#{ENV['APPLICATION_HOST'] || 'app.amoslabs.com'}"

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # SES configuration (via aws-sdk-rails)
  config.action_mailer.delivery_method = :aws_sdk
  config.action_mailer.perform_deliveries = true
  # Ensure AWS_REGION is set in environment variables

  # Add your actual domain to allowed hosts
  config.hosts << ENV["APPLICATION_HOST"]
  config.hosts << "www.#{ENV['APPLICATION_HOST']}"
  config.hosts << "app.#{ENV['APPLICATION_HOST']}"

  # Allow Heroku app domain
  config.hosts << "nuvola-marketing-agent-86aa0618d72d.herokuapp.com"

  # Allow amoslabs.com domains
  config.hosts << "amoslabs.com"
  config.hosts << "www.amoslabs.com"
  config.hosts << "app.amoslabs.com"
  config.hosts << "dev.amoslabs.com"

  # Allow landing page subdomains (*.lp.amoslabs.com)
  config.hosts << "lp.amoslabs.com"
  config.hosts << /.*\.lp\.amoslabs\.com$/

  # Legacy everloom.ai domains (for migration period)
  config.hosts << "everloom.ai"
  config.hosts << "www.everloom.ai"
  config.hosts << "app.everloom.ai"

  # Allow cruxmarketing.ai domains
  config.hosts << "cruxmarketing.ai"
  config.hosts << "www.cruxmarketing.ai"
  config.hosts << "app.cruxmarketing.ai"

  # Allow ALB DNS names
  config.hosts << /.*\.elb\.amazonaws\.com$/
  
  # Allow ALB health check IPs (AWS internal IPs)
  config.hosts << /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/

  # Skip host authorization for health checks
  config.host_authorization = {
    exclude: ->(request) {
      request.path == "/up" ||
      request.path == "/health" ||
      request.path == "/health_check" ||
      request.user_agent =~ /ELB-HealthChecker/
    }
  }
end
