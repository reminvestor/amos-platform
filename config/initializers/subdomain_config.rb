# Subdomain configuration for different environments
module SubdomainConfig
  def self.app_subdomains
    if Rails.env.production?
      ["app"]
    else
      # In development/staging, accept both 'app' and 'dev' subdomains
      ["app", "dev"]
    end
  end
end
