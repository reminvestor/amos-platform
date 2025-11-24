# Set up mailer URLs to work properly with subdomains
if Rails.env.production?
  # Define the host for email links
  # APPLICATION_HOST should be the full hostname (e.g., "app.amoslabs.com" or "dev.amoslabs.com")
  mailer_host = ENV['APPLICATION_HOST'] || "app.amoslabs.com"

  # Set default URL options for mailers
  Rails.application.config.action_mailer.default_url_options = {
    host: mailer_host,
    protocol: "https"
  }

  # Set default URL options for routes - these will be used in route helpers
  Rails.application.routes.default_url_options = {
    host: mailer_host,
    protocol: "https"
  }
end
