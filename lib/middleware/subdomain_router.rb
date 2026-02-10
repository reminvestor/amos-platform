# frozen_string_literal: true

# lib/middleware/subdomain_router.rb
# Middleware to route landing page subdomain requests to the appropriate controller
# Handles:
#   1. Built-in subdomains: mypage.lp.amoslabs.com -> /lp/mypage
#   2. Custom domains: example.com -> /lp/custom/:domain_id (via CNAME to *.custom.amoslabs.co)
#
# This middleware intercepts requests and rewrites the path
# to route through the LpController for subdomain-based landing page serving.
#
# Note: Namespaced as Middleware::SubdomainRouter to match Zeitwerk autoloading expectations
module Middleware
  class SubdomainRouter
    # Cache custom domain lookups for 5 minutes to avoid DB hits on every request
    CUSTOM_DOMAIN_CACHE_TTL = 5.minutes

    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)
      host = request.host.to_s.downcase

      # ─── Check 1: Built-in landing page subdomains ───
      # Pattern: {subdomain}.lp.{domain} (e.g., mypage.lp.amoslabs.com)
      if SubdomainConfig.landing_page_subdomain?(host)
        subdomain = SubdomainConfig.extract_landing_page_subdomain(host)

        if subdomain.present?
          env["LANDING_PAGE_SUBDOMAIN"] = subdomain
          env["ORIGINAL_PATH_INFO"] = env["PATH_INFO"]

          original_path = env["PATH_INFO"].to_s

          if original_path == "/" || original_path.empty?
            env["PATH_INFO"] = "/lp/#{subdomain}"
            env["REQUEST_PATH"] = "/lp/#{subdomain}"
          elsif original_path.start_with?("/api/v1/landing_pages/")
            # Allow API calls to pass through (form submissions, etc.)
          else
            env["PATH_INFO"] = "/lp/#{subdomain}"
            env["REQUEST_PATH"] = "/lp/#{subdomain}"
          end
        end

      # ─── Check 2: Custom domain routing ───
      # If the host is not a known platform domain, look it up as a custom domain
      elsif custom_domain_request?(host)
        domain_record = lookup_custom_domain(host)

        if domain_record
          env["CUSTOM_DOMAIN_ID"] = domain_record[:id]
          env["CUSTOM_DOMAIN_HOST"] = host
          env["ORIGINAL_PATH_INFO"] = env["PATH_INFO"]

          original_path = env["PATH_INFO"].to_s

          if original_path == "/" || original_path.empty? || !original_path.start_with?("/api/")
            env["PATH_INFO"] = "/lp/custom/#{domain_record[:id]}"
            env["REQUEST_PATH"] = "/lp/custom/#{domain_record[:id]}"
          end
        end
      end

      @app.call(env)
    end

    private

    # Check if this host could be a custom domain (not a platform domain)
    def custom_domain_request?(host)
      return false if host.blank?
      return false if host.include?("localhost") || host.include?("lvh.me")
      return false if host.include?("amoslabs.com") || host.include?("amoslabs.co")
      return false if host =~ /\A\d+\.\d+\.\d+\.\d+\z/ # Skip IP addresses

      # Looks like a real external domain
      true
    end

    # Look up a custom domain record (with caching)
    def lookup_custom_domain(host)
      cache_key = "subdomain_router:custom_domain:#{host}"

      Rails.cache.fetch(cache_key, expires_in: CUSTOM_DOMAIN_CACHE_TTL) do
        domain = CustomDomain.where(web_status: "verified")
                             .where("domain_name = :host OR CONCAT(subdomain, '.', domain_name) = :host", host: host)
                             .first

        if domain
          { id: domain.id, entity_id: domain.entity_id }
        else
          nil
        end
      end
    rescue => e
      Rails.logger.error "[SubdomainRouter] Custom domain lookup failed for #{host}: #{e.message}"
      nil
    end
  end
end
