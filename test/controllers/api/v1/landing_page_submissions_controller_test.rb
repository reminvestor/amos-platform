# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class LandingPageSubmissionsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create a published landing page for submissions
        @landing_page = LandingPage.create!(
          user: @user,
          entity: @entity,
          title: "Test Landing Page",
          slug: "test-landing-page-#{SecureRandom.hex(4)}",
          status: "published",
          html_content: "<h1>Test</h1>"
        )

        # Create test submissions
        @submission = LandingPageSubmission.create!(
          landing_page: @landing_page,
          form_type: "contact",
          status: "pending",
          submission_data: {
            "email" => "test@example.com",
            "first_name" => "Test",
            "last_name" => "User",
            "message" => "Hello"
          },
          submitted_at: Time.current
        )
      end

      teardown do
        LandingPageSubmission.where(landing_page: @landing_page).destroy_all if @landing_page
        @landing_page&.destroy
      end

      # ====================================================================
      # Helper Methods
      # ====================================================================

      def auth_headers
        { "Authorization" => "Bearer #{@user.api_key}" }
      end

      # ====================================================================
      # CREATE Tests (Public endpoint - no auth required)
      # ====================================================================

      test "should create submission without authentication" do
        assert_difference("LandingPageSubmission.count", 1) do
          post api_v1_landing_page_submissions_path, params: {
            landing_page_slug: @landing_page.slug,
            email: "newuser@example.com",
            first_name: "New",
            last_name: "User",
            message: "Test submission"
          }, as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert response_body.key?("submission_id")
      end

      test "create returns error for non-existent landing page" do
        post api_v1_landing_page_submissions_path, params: {
          landing_page_slug: "non-existent-page",
          email: "test@example.com"
        }, as: :json

        assert_response :not_found

        response_body = JSON.parse(response.body)
        assert_equal false, response_body["success"]
      end

      test "create returns error for invalid form data" do
        post api_v1_landing_page_submissions_path, params: {
          landing_page_slug: @landing_page.slug,
          # Missing required email
          message: "Just a message"
        }, as: :json

        assert_response :unprocessable_entity

        response_body = JSON.parse(response.body)
        assert_equal false, response_body["success"]
        assert response_body["errors"].any?
      end

      test "create sets form type based on data" do
        post api_v1_landing_page_submissions_path, params: {
          landing_page_slug: @landing_page.slug,
          email: "newsletter@example.com",
          newsletter_signup: "true"
        }, as: :json

        assert_response :created

        submission = LandingPageSubmission.last
        assert_equal "newsletter", submission.form_type
      end

      test "create captures UTM parameters" do
        post api_v1_landing_page_submissions_path, params: {
          landing_page_slug: @landing_page.slug,
          email: "utm@example.com",
          first_name: "UTM",
          last_name: "Test",
          utm_source: "google",
          utm_medium: "cpc",
          utm_campaign: "summer_sale"
        }, as: :json

        assert_response :created

        submission = LandingPageSubmission.last
        assert_equal "google", submission.utm_source
        assert_equal "cpc", submission.utm_medium
        assert_equal "summer_sale", submission.utm_campaign
      end

      # ====================================================================
      # INDEX Tests (Authenticated endpoint)
      # ====================================================================

      test "should get submissions list with valid token" do
        get api_v1_landing_page_submissions_path, params: {
          landing_page_id: @landing_page.id
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert response_body.key?("submissions")
        assert response_body.key?("total_count")
        assert response_body.key?("conversion_rate")
      end

      test "submissions list returns expected fields" do
        get api_v1_landing_page_submissions_path, params: {
          landing_page_id: @landing_page.id
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        submissions = response_body["submissions"]

        assert submissions.any?

        submission = submissions.find { |s| s["id"] == @submission.id }
        assert_not_nil submission
        assert_equal "contact", submission["form_type"]
        assert_equal "pending", submission["status"]
        assert submission.key?("landing_page")
      end

      test "index requires authentication" do
        get api_v1_landing_page_submissions_path, params: {
          landing_page_id: @landing_page.id
        }, as: :json

        assert_response :unauthorized
      end

      test "index returns 404 for non-existent landing page" do
        get api_v1_landing_page_submissions_path, params: {
          landing_page_id: 999999
        }, headers: auth_headers, as: :json

        assert_response :not_found
      end

      # ====================================================================
      # SHOW Tests (Authenticated endpoint)
      # ====================================================================

      test "should get submission details with valid token" do
        get api_v1_landing_page_submission_path(@submission), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal @submission.id, response_body["submission"]["id"]
      end

      test "show requires authentication" do
        get api_v1_landing_page_submission_path(@submission), as: :json

        assert_response :unauthorized
      end

      test "should return 404 for non-existent submission" do
        get api_v1_landing_page_submission_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      # ====================================================================
      # MARK_PROCESSED Tests (Authenticated endpoint)
      # ====================================================================

      test "should mark submission as processed" do
        post mark_processed_api_v1_landing_page_submission_path(@submission), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]

        @submission.reload
        assert_equal "processed", @submission.status
      end

      test "mark_processed requires authentication" do
        post mark_processed_api_v1_landing_page_submission_path(@submission), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # SPAM Tests (Authenticated endpoint)
      # ====================================================================

      test "should mark submission as spam" do
        post spam_api_v1_landing_page_submission_path(@submission), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]

        @submission.reload
        assert_equal "spam", @submission.status
      end

      test "spam requires authentication" do
        post spam_api_v1_landing_page_submission_path(@submission), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # EXPORT Tests (Authenticated endpoint)
      # ====================================================================

      test "export requires authentication" do
        get export_api_v1_landing_page_submissions_path, as: :json

        assert_response :unauthorized
      end

      test "should export submissions as CSV" do
        get export_api_v1_landing_page_submissions_path, params: {
          landing_page_id: @landing_page.id
        }, headers: auth_headers

        assert_response :success
        assert_equal "text/csv", response.content_type.split(";").first
      end
    end
  end
end
