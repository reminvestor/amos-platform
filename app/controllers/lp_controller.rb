# frozen_string_literal: true

# Controller for serving landing pages via subdomain URLs
# Handles requests like: mypage.lp.amoslabs.com
#
# The SubdomainRouter middleware rewrites these requests to /lp/:subdomain
# which is then handled by this controller.
class LpController < ApplicationController
  include LandingPageRendering

  # No authentication required for public landing pages
  skip_before_action :authenticate_user!

  # Serve a landing page by its subdomain
  # GET /lp/:subdomain
  def show
    subdomain = params[:subdomain] || request.env["LANDING_PAGE_SUBDOMAIN"]

    @landing_page = LandingPage.published.find_by!(subdomain: subdomain&.downcase)

    # Track the page view
    track_landing_page_view(@landing_page)

    # Render the complete HTML content
    clean_html = prepare_landing_page_html(@landing_page)

    if clean_html.present?
      render html: clean_html.html_safe
    else
      render plain: "This landing page is not yet available.", status: :not_found
    end
  rescue ActiveRecord::RecordNotFound
    render file: "#{Rails.root}/public/404.html", layout: false, status: :not_found
  end

  private

  # Track landing page views for analytics
  def track_landing_page_view(landing_page)
    # Increment view count in metadata
    views = landing_page.metadata["views_count"].to_i
    landing_page.update_column(:metadata, landing_page.metadata.merge("views_count" => views + 1))
  rescue StandardError => e
    # Don't fail the request if tracking fails
    Rails.logger.error "Failed to track landing page view: #{e.message}"
  end
end
