require "test_helper"

module Api
  module V1
    class CampaignsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        @campaign = campaigns(:one)
        @campaign.update!(entity: @entity, user: @user)
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

      test "should get campaigns list with valid token" do
        get api_v1_campaigns_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
        assert response_body.key?("pagination")
      end

      test "campaigns list returns expected fields" do
        get api_v1_campaigns_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        campaigns = response_body["data"]

        assert campaigns.any?

        campaign = campaigns.first
        assert campaign.key?("id")
        assert campaign.key?("name")
        assert campaign.key?("subject")
        assert campaign.key?("status")
        assert campaign.key?("contact_count")
        assert campaign.key?("sent_count")
        assert campaign.key?("created_at")
        assert campaign.key?("updated_at")
      end

      test "campaigns list supports search filter" do
        get api_v1_campaigns_path, params: { search: "Summer" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        campaigns = response_body["data"]

        assert campaigns.all? { |c| c["name"].downcase.include?("summer") }
      end

      test "campaigns list supports status filter" do
        get api_v1_campaigns_path, params: { status: "draft" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        campaigns = response_body["data"]

        assert campaigns.all? { |c| c["status"] == "draft" }
      end

      test "campaigns list requires authentication" do
        get api_v1_campaigns_path, as: :json

        assert_response :unauthorized
      end

      test "campaigns list returns pagination info" do
        get api_v1_campaigns_path, headers: auth_headers, as: :json

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

      test "should get campaign details with valid token" do
        get api_v1_campaign_path(@campaign), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @campaign.id, response_body["id"]
        assert_equal @campaign.name, response_body["name"]
      end

      test "campaign show returns detailed fields" do
        get api_v1_campaign_path(@campaign), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("content")
        assert response_body.key?("contact_groups")
      end

      test "should return 404 for non-existent campaign" do
        get api_v1_campaign_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "campaign show requires authentication" do
        get api_v1_campaign_path(@campaign), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CREATE Tests
      # ====================================================================

      test "should create campaign with valid params" do
        assert_difference "Campaign.count", 1 do
          post api_v1_campaigns_path,
            params: { name: "New Test Campaign", status: "draft" },
            headers: auth_headers,
            as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert_equal "New Test Campaign", response_body["name"]
        assert_equal "draft", response_body["status"]
      end

      test "create campaign requires authentication" do
        post api_v1_campaigns_path,
          params: { name: "New Campaign", subject: "Subject" },
          as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # UPDATE Tests
      # ====================================================================

      test "should update campaign with valid params" do
        patch api_v1_campaign_path(@campaign),
          params: { name: "Updated Campaign Name" },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "Updated Campaign Name", response_body["name"]
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should destroy campaign" do
        assert_difference "Campaign.count", -1 do
          delete api_v1_campaign_path(@campaign), headers: auth_headers, as: :json
        end

        assert_response :no_content
      end
    end
  end
end
