# Subdomain configuration for different environments
module SubdomainConfig
  def self.app_subdomains
    if Rails.env.production?
      # In production, check if we're running in dev environment (dev.amoslabs.com)
      if ENV['APP_DOMAIN']&.start_with?('dev.')
        ["app", "dev"]
      else
        ["app"]
      end
    else
      # In development/staging, accept 'app', 'dev', and empty string (no subdomain)
      # Empty string allows localhost:3000 without subdomain to be treated as app subdomain
      ["app", "dev", ""]
    end
  end

  # Get the host for landing page subdomains
  # Landing pages are accessible at: {subdomain}.lp.{domain}
  # e.g., mypage.lp.amoslabs.com
  def self.landing_page_host
    if Rails.env.production?
      domain = ENV.fetch("APP_DOMAIN", "amoslabs.com")
      # Remove any existing subdomain prefix (e.g., "app.amoslabs.com" -> "amoslabs.com")
      domain = domain.sub(/\A(app|dev)\./, "")
      "lp.#{domain}"
    else
      # Use lvh.me for local development (resolves to localhost)
      "lp.lvh.me:3000"
    end
  end

  # Check if a host matches the landing page subdomain pattern
  # @param host [String] The host to check (e.g., "mypage.lp.amoslabs.com")
  # @return [Boolean]
  def self.landing_page_subdomain?(host)
    return false unless host.present?
    host.downcase.include?(".lp.")
  end

  # Extract the subdomain from a landing page host
  # @param host [String] The host (e.g., "mypage.lp.amoslabs.com")
  # @return [String, nil] The subdomain (e.g., "mypage") or nil
  def self.extract_landing_page_subdomain(host)
    return nil unless landing_page_subdomain?(host)
    host.downcase.split(".lp.").first
  end
end
