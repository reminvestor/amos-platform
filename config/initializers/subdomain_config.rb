# Subdomain configuration for different environments
module SubdomainConfig
  def self.app_subdomains
    if Rails.env.production?
      # In production, check if we're running in dev environment (dev.amoslabs.com)
      if ENV['ECS_CLUSTER']&.include?('dev') || ENV['RAILS_ENV_NAME'] == 'dev'
        ["app", "dev"]
      else
        ["app"]
      end
    else
      # In development/staging, accept both 'app' and 'dev' subdomains
      ["app", "dev"]
    end
  end
end
