# Set up mailer URLs to work properly with subdomains
if Rails.env.production?
  # Define the subdomain host for email tracking
  subdomain_host = "app.#{ENV['APPLICATION_HOST'] || 'everloom.ai'}"
  
  # Set default URL options for mailers
  Rails.application.config.action_mailer.default_url_options = { 
    host: subdomain_host, 
    protocol: 'https' 
  }
  
  # Set default URL options for routes - these will be used in route helpers
  Rails.application.routes.default_url_options = { 
    host: subdomain_host, 
    protocol: 'https' 
  }
end 