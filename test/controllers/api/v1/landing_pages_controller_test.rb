require "test_helper"

module Api
  module V1
    class LandingPagesControllerTest < ActionDispatch::IntegrationTest
      setup do
        # Clear API cache to avoid stale user data
        Rails.cache.clear

        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Reload user to ensure entity relationship is fresh
        @user.reload

        # Create a landing page directly for this entity/user to avoid fixture entity mismatch
        @landing_page = LandingPage.create!(
          title: "Test Landing Page",
          slug: "test-landing-page-#{SecureRandom.hex(4)}",
          status: "draft",
          entity: @entity,
          user: @user
        )
      end

      teardown do
        # Clean up the created landing page
        @landing_page&.destroy
      end

      # ====================================================================
      # Helper Methods
      # ====================================================================

      def auth_headers
        { "Authorization" => "Bearer #{@user.api_key}" }
      end

      # ====================================================================
      # INDEX Tests
      # ====================================================================

      test "should get landing pages list with valid token" do
        get api_v1_landing_pages_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
        assert response_body.key?("pagination")
      end

      test "landing pages list returns expected fields" do
        get api_v1_landing_pages_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        pages = response_body["data"]

        assert pages.any?

        page = pages.first
        assert page.key?("id")
        assert page.key?("title")
        assert page.key?("slug")
        assert page.key?("status")
        assert page.key?("view_count")
        assert page.key?("submission_count")
        assert page.key?("created_at")
        assert page.key?("updated_at")
      end

      test "landing pages list supports search filter" do
        get api_v1_landing_pages_path, params: { search: "Test" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        pages = response_body["data"]

        assert pages.any? { |p| p["title"].downcase.include?("test") }
      end

      test "landing pages list supports status filter" do
        get api_v1_landing_pages_path, params: { status: "published" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        pages = response_body["data"]

        assert pages.all? { |p| p["status"] == "published" }
      end

      test "landing pages list requires authentication" do
        get api_v1_landing_pages_path, as: :json

        assert_response :unauthorized
      end

      test "landing pages list returns pagination info" do
        get api_v1_landing_pages_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        pagination = response_body["pagination"]

        assert pagination.key?("current_page")
        assert pagination.key?("total_pages")
        assert pagination.key?("total_count")
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get landing page details with valid token" do
        get api_v1_landing_page_path(@landing_page), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @landing_page.id, response_body["id"]
        assert response_body["title"].include?("Test Landing Page")
      end

      test "landing page show returns detailed fields" do
        get api_v1_landing_page_path(@landing_page), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("content")
      end

      test "should return 404 for non-existent landing page" do
        get api_v1_landing_page_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "landing page show requires authentication" do
        get api_v1_landing_page_path(@landing_page), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CREATE Tests
      # ====================================================================

      test "should create landing page with valid params" do
        assert_difference "LandingPage.count", 1 do
          post api_v1_landing_pages_path,
            params: { title: "New Landing Page", slug: "new-landing-page-#{SecureRandom.hex(4)}" },
            headers: auth_headers,
            as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert_equal "New Landing Page", response_body["title"]
      end

      test "create landing page requires authentication" do
        post api_v1_landing_pages_path,
          params: { title: "New Page", slug: "new-page" },
          as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # UPDATE Tests
      # ====================================================================

      test "should update landing page with valid params" do
        patch api_v1_landing_page_path(@landing_page),
          params: { title: "Updated Landing Page Title" },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "Updated Landing Page Title", response_body["title"]
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should destroy landing page" do
        assert_difference "LandingPage.count", -1 do
          delete api_v1_landing_page_path(@landing_page), headers: auth_headers, as: :json
        end

        assert_response :no_content
      end

      # ====================================================================
      # PUBLISH/UNPUBLISH Tests
      # ====================================================================

      test "should publish landing page" do
        @landing_page.update!(status: "draft")

        post publish_api_v1_landing_page_path(@landing_page), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "published", response_body["status"]
      end

      test "should unpublish landing page" do
        @landing_page.update!(status: "published")

        post unpublish_api_v1_landing_page_path(@landing_page), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "draft", response_body["status"]
      end
    end
  end
end
