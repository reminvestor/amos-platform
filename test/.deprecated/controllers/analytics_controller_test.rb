# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class AnalyticsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create test campaigns (stats computed from mailgun_stats JSON)
        @campaign = Campaign.create!(
          entity: @entity,
          user: @user,
          name: "Test Campaign",
          status: "completed",
          mailgun_stats: { "delivered" => 100, "opened" => 25, "clicked" => 5, "bounced" => 1 }
        )

        @active_campaign = Campaign.create!(
          entity: @entity,
          user: @user,
          name: "Active Campaign",
          status: "in_progress",
          mailgun_stats: { "delivered" => 50 }
        )

        # Create test landing page (stats computed from submissions and metadata)
        @landing_page = LandingPage.create!(
          entity: @entity,
          user: @user,
          title: "Test Landing Page",
          slug: "test-landing-page-analytics",
          status: "published",
          html_content: "<html><body>Test</body></html>",
          metadata: { "view_count" => 1000 }
        )

        # Create submissions for the landing page
        50.times do
          LandingPageSubmission.create!(
            landing_page: @landing_page,
            form_type: "contact",
            submission_data: { email: "test#{rand(1000)}@example.com" }
          )
        end
      end

      teardown do
        LandingPageSubmission.where(landing_page: @landing_page).destroy_all if @landing_page
        Campaign.where(entity: @entity, name: ["Test Campaign", "Active Campaign"]).destroy_all
        LandingPage.where(entity: @entity, slug: "test-landing-page-analytics").destroy_all
      end

      # ====================================================================
      # Helper Methods
      # ====================================================================

      def auth_headers
        { "Authorization" => "Bearer #{@user.api_key}" }
      end

      # ====================================================================
      # DASHBOARD Tests
      # ====================================================================

      test "should get analytics dashboard with valid token" do
        get dashboard_api_v1_analytics_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("summary")
        assert response_body.key?("campaigns")
        assert response_body.key?("landing_pages")
        assert response_body.key?("recent_activity")
      end

      test "dashboard returns summary stats" do
        get dashboard_api_v1_analytics_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        summary = response_body["summary"]

        assert summary.key?("total_campaigns")
        assert summary.key?("active_campaigns")
        assert summary.key?("total_contacts")
        assert summary.key?("active_contacts")
        assert summary.key?("total_landing_pages")
        assert summary.key?("published_landing_pages")
      end

      test "dashboard returns campaign stats" do
        get dashboard_api_v1_analytics_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        campaigns = response_body["campaigns"]

        assert campaigns.key?("total_sent")
        assert campaigns.key?("avg_open_rate")
        assert campaigns.key?("avg_click_rate")
        assert campaigns.key?("avg_bounce_rate")
      end

      test "dashboard returns landing page stats" do
        get dashboard_api_v1_analytics_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        landing_pages = response_body["landing_pages"]

        assert landing_pages.key?("total_views")
        assert landing_pages.key?("total_submissions")
        assert landing_pages.key?("conversion_rate")
      end

      test "dashboard requires authentication" do
        get dashboard_api_v1_analytics_path, as: :json

        assert_response :unauthorized
      end

      test "dashboard rejects invalid token" do
        get dashboard_api_v1_analytics_path,
          headers: { "Authorization" => "Bearer invalid_token" },
          as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CAMPAIGNS Tests
      # ====================================================================

      test "should get campaign analytics with valid token" do
        get campaigns_api_v1_analytics_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
      end

      test "campaign analytics returns expected fields" do
        get campaigns_api_v1_analytics_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        campaigns = response_body["data"]

        campaign = campaigns.find { |c| c["id"] == @campaign.id }
        assert_not_nil campaign
        assert_equal "Test Campaign", campaign["name"]
        assert_equal "completed", campaign["status"]
        assert_equal 100, campaign["sent_count"]
        assert campaign.key?("open_rate")
        assert campaign.key?("click_rate")
        assert campaign.key?("bounce_rate")
        assert campaign.key?("created_at")
      end

      test "campaign analytics supports limit param" do
        get campaigns_api_v1_analytics_path, params: { limit: 1 }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal 1, response_body["data"].size
      end

      test "campaign analytics requires authentication" do
        get campaigns_api_v1_analytics_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # LANDING_PAGES Tests
      # ====================================================================

      test "should get landing page analytics with valid token" do
        get landing_pages_api_v1_analytics_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
      end

      test "landing page analytics returns expected fields" do
        get landing_pages_api_v1_analytics_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        pages = response_body["data"]

        page = pages.find { |p| p["id"] == @landing_page.id }
        assert_not_nil page
        assert_equal "Test Landing Page", page["title"]
        assert_equal "test-landing-page-analytics", page["slug"]
        assert_equal "published", page["status"]
        assert_equal 1000, page["view_count"]
        assert_equal 50, page["submission_count"]
        assert page.key?("conversion_rate")
        assert page.key?("created_at")
      end

      test "landing page analytics calculates conversion rate" do
        get landing_pages_api_v1_analytics_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        page = response_body["data"].find { |p| p["id"] == @landing_page.id }

        # 50 submissions / 1000 views * 100 = 5.0%
        assert_equal 5.0, page["conversion_rate"]
      end

      test "landing page analytics supports limit param" do
        get landing_pages_api_v1_analytics_path, params: { limit: 1 }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal 1, response_body["data"].size
      end

      test "landing page analytics requires authentication" do
        get landing_pages_api_v1_analytics_path, as: :json

        assert_response :unauthorized
      end
    end
  end
end
