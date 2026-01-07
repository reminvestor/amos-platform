# frozen_string_literal: true

require "test_helper"

module Api
  class BusinessProfilesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @entity = entities(:one)
      @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

      # Ensure user has a business profile - create directly with entity
      @business_profile = @user.business_profile || @user.create_business_profile(
        entity: @entity,
        name: "Test Business",
        industry: "Technology",
        description: "A test business for testing",
        website: "https://testbusiness.com",
        values: "Innovation, Quality",
        target_audience: "Developers",
        tone_of_voice: "Professional"
      )
      @business_profile.update!(
        entity: @entity,
        name: "Test Business",
        industry: "Technology",
        description: "A test business for testing",
        website: "https://testbusiness.com",
        values: "Innovation, Quality",
        target_audience: "Developers",
        tone_of_voice: "Professional"
      )
    end

    teardown do
      # Clean up
    end

    # ====================================================================
    # Helper Methods
    # ====================================================================

    def auth_headers
      { "Authorization" => "Bearer #{@user.api_key}" }
    end

    # ====================================================================
    # SHOW Tests
    # ====================================================================

    test "should get business profile with valid token" do
      get api_business_profile_path, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body.key?("id")
      assert response_body.key?("name")
      assert response_body.key?("industry")
    end

    test "business profile returns expected fields" do
      get api_business_profile_path, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert_equal "Test Business", response_body["name"]
      assert_equal "Technology", response_body["industry"]
      assert_equal "A test business for testing", response_body["description"]
      assert_equal "https://testbusiness.com", response_body["website"]
      assert_equal "Innovation, Quality", response_body["values"]
      assert_equal "Developers", response_body["target_audience"]
      assert_equal "Professional", response_body["tone_of_voice"]
      assert response_body.key?("style_guidelines")
    end

    test "show requires authentication" do
      get api_business_profile_path, as: :json

      assert_response :unauthorized
    end

    test "show rejects invalid token" do
      get api_business_profile_path,
        headers: { "Authorization" => "Bearer invalid_token" },
        as: :json

      assert_response :unauthorized
    end

    # ====================================================================
    # UPDATE Tests
    # ====================================================================

    test "should update business profile with valid params" do
      patch api_business_profile_path, params: {
        business_profile: {
          name: "Updated Business Name",
          industry: "Finance",
          description: "Updated description"
        }
      }, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert_equal true, response_body["success"]
      assert_equal "Updated Business Name", response_body["profile"]["name"]
      assert_equal "Finance", response_body["profile"]["industry"]
      assert_equal "Updated description", response_body["profile"]["description"]
    end

    test "update returns success message" do
      patch api_business_profile_path, params: {
        business_profile: {
          name: "New Name"
        }
      }, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert_equal true, response_body["success"]
      assert response_body.key?("message")
    end

    test "update persists changes" do
      patch api_business_profile_path, params: {
        business_profile: {
          values: "New Values, New Mission",
          tone_of_voice: "Casual"
        }
      }, headers: auth_headers, as: :json

      assert_response :success

      @business_profile.reload
      assert_equal "New Values, New Mission", @business_profile.values
      assert_equal "Casual", @business_profile.tone_of_voice
    end

    test "update requires authentication" do
      patch api_business_profile_path, params: {
        business_profile: { name: "Hacked" }
      }, as: :json

      assert_response :unauthorized
    end

    test "update can set style guidelines with colors" do
      patch api_business_profile_path, params: {
        business_profile: {
          style_colors: "#FF0000\n#00FF00\n#0000FF",
          style_typography: "Sans-serif",
          style_aesthetic: "Modern"
        }
      }, headers: auth_headers, as: :json

      assert_response :success

      @business_profile.reload
      assert_not_nil @business_profile.style_guidelines
      assert_equal ["#FF0000", "#00FF00", "#0000FF"], @business_profile.style_guidelines["colors"]
      assert_equal "Sans-serif", @business_profile.style_guidelines["typography"]
      assert_equal "Modern", @business_profile.style_guidelines["aesthetic"]
    end

    test "update partial fields without affecting others" do
      original_description = @business_profile.description

      patch api_business_profile_path, params: {
        business_profile: {
          name: "Only Name Changed"
        }
      }, headers: auth_headers, as: :json

      assert_response :success

      @business_profile.reload
      assert_equal "Only Name Changed", @business_profile.name
      assert_equal original_description, @business_profile.description
    end
  end
end
