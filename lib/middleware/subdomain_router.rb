# frozen_string_literal: true

# lib/middleware/subdomain_router.rb
# Middleware to route landing page subdomain requests to the appropriate controller
# Handles URLs like: mypage.lp.amoslabs.com -> /lp/mypage
#
# This middleware intercepts requests to *.lp.{domain} and rewrites the path
# to route through the LpController for subdomain-based landing page serving.
#
# Note: Namespaced as Middleware::SubdomainRouter to match Zeitwerk autoloading expectations
module Middleware
  class SubdomainRouter
    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)
      host = request.host.to_s.downcase

      # Check if this is a landing page subdomain request
      # Pattern: {subdomain}.lp.{domain} (e.g., mypage.lp.amoslabs.com)
      if SubdomainConfig.landing_page_subdomain?(host)
        subdomain = SubdomainConfig.extract_landing_page_subdomain(host)

        if subdomain.present?
          # Store original values for debugging
          env["LANDING_PAGE_SUBDOMAIN"] = subdomain
          env["ORIGINAL_PATH_INFO"] = env["PATH_INFO"]

          # Rewrite the request to the landing page controller
          # The root path "/" becomes "/lp/{subdomain}"
          original_path = env["PATH_INFO"].to_s

          if original_path == "/" || original_path.empty?
            # Root request - show the landing page
            env["PATH_INFO"] = "/lp/#{subdomain}"
            env["REQUEST_PATH"] = "/lp/#{subdomain}"
          elsif original_path.start_with?("/api/v1/landing_pages/")
            # Allow API calls to pass through (form submissions, etc.)
            # These are handled by the API controller
          else
            # Other paths on the subdomain - could be assets, etc.
            # For now, just serve the landing page for any path
            env["PATH_INFO"] = "/lp/#{subdomain}"
            env["REQUEST_PATH"] = "/lp/#{subdomain}"
          end
        end
      end

      @app.call(env)
    end
  end
end
