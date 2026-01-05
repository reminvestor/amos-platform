# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class OpportunitiesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create a test contact for opportunities
        @contact = Contact.create!(
          user: @user,
          entity: @entity,
          email: "opportunity_contact@test.com",
          first_name: "Test",
          last_name: "Contact",
          status: "active"
        )

        # Create test opportunities
        @opportunity = Opportunity.create!(
          entity: @entity,
          contact: @contact,
          user: @user,
          name: "Test Opportunity",
          stage: "lead",
          value: 10000,
          expected_close_date: 30.days.from_now
        )

        @closed_opportunity = Opportunity.create!(
          entity: @entity,
          contact: @contact,
          user: @user,
          name: "Closed Opportunity",
          stage: "closed_won",
          value: 5000,
          actual_close_date: 1.day.ago
        )
      end

      teardown do
        Opportunity.where(contact: @contact).destroy_all if @contact
        @contact&.destroy
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

      test "should get opportunities list with valid token" do
        get api_v1_opportunities_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert response_body.key?("opportunities")
        assert response_body.key?("total_count")
        assert response_body.key?("pipeline_stats")
      end

      test "opportunities list returns expected fields" do
        get api_v1_opportunities_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        opportunities = response_body["opportunities"]

        assert opportunities.any?

        opportunity = opportunities.find { |o| o["id"] == @opportunity.id }
        assert_not_nil opportunity
        assert_equal "Test Opportunity", opportunity["name"]
        assert_equal "lead", opportunity["stage"]
        assert_equal 10000, opportunity["value"].to_i
        assert opportunity.key?("contact")
        assert opportunity.key?("stage_label")
      end

      test "opportunities list can filter by stage" do
        get api_v1_opportunities_path, params: { stage: "lead" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        opportunity_ids = response_body["opportunities"].map { |o| o["id"] }

        assert_includes opportunity_ids, @opportunity.id
        assert_not_includes opportunity_ids, @closed_opportunity.id
      end

      test "opportunities list can filter by status" do
        get api_v1_opportunities_path, params: { status: "won" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        opportunity_ids = response_body["opportunities"].map { |o| o["id"] }

        assert_not_includes opportunity_ids, @opportunity.id
        assert_includes opportunity_ids, @closed_opportunity.id
      end

      test "opportunities list requires authentication" do
        get api_v1_opportunities_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # PIPELINE Tests
      # ====================================================================

      test "should get pipeline view" do
        get pipeline_api_v1_opportunities_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert response_body.key?("pipeline")
        assert response_body.key?("stats")

        pipeline = response_body["pipeline"]
        assert pipeline.key?("lead")
        assert pipeline.key?("qualified")
        assert pipeline.key?("proposal")
      end

      test "pipeline requires authentication" do
        get pipeline_api_v1_opportunities_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get opportunity details with valid token" do
        get api_v1_opportunity_path(@opportunity), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal @opportunity.id, response_body["opportunity"]["id"]
        assert_equal "Test Opportunity", response_body["opportunity"]["name"]
      end

      test "should return 404 for non-existent opportunity" do
        get api_v1_opportunity_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "opportunity show requires authentication" do
        get api_v1_opportunity_path(@opportunity), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CREATE Tests
      # ====================================================================

      test "should create opportunity with valid params" do
        assert_difference("Opportunity.count", 1) do
          post api_v1_opportunities_path, params: {
            opportunity: {
              contact_id: @contact.id,
              name: "New Opportunity",
              stage: "lead",
              value: 15000,
              expected_close_date: 60.days.from_now
            }
          }, headers: auth_headers, as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal "New Opportunity", response_body["opportunity"]["name"]
      end

      test "create returns error for invalid params" do
        post api_v1_opportunities_path, params: {
          opportunity: {
            name: "",  # Name is required
            stage: "invalid_stage"
          }
        }, headers: auth_headers, as: :json

        assert_response :unprocessable_entity

        response_body = JSON.parse(response.body)
        assert_equal false, response_body["success"]
        assert response_body["errors"].any?
      end

      test "create requires authentication" do
        post api_v1_opportunities_path, params: {
          opportunity: {
            contact_id: @contact.id,
            name: "New Opportunity",
            stage: "lead"
          }
        }, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # UPDATE Tests
      # ====================================================================

      test "should update opportunity with valid params" do
        patch api_v1_opportunity_path(@opportunity), params: {
          opportunity: {
            name: "Updated Opportunity Name",
            value: 20000
          }
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal "Updated Opportunity Name", response_body["opportunity"]["name"]
        assert_equal 20000, response_body["opportunity"]["value"].to_i
      end

      test "update requires authentication" do
        patch api_v1_opportunity_path(@opportunity), params: {
          opportunity: { name: "Hacked" }
        }, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should destroy opportunity" do
        opportunity_to_delete = Opportunity.create!(
          entity: @entity,
          contact: @contact,
          user: @user,
          name: "To Delete",
          stage: "lead"
        )

        assert_difference("Opportunity.count", -1) do
          delete api_v1_opportunity_path(opportunity_to_delete), headers: auth_headers, as: :json
        end

        assert_response :success
      end

      test "destroy requires authentication" do
        delete api_v1_opportunity_path(@opportunity), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # MOVE_STAGE Tests
      # ====================================================================

      test "should move opportunity to new stage" do
        post move_stage_api_v1_opportunity_path(@opportunity), params: {
          stage: "qualified"
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal "qualified", response_body["opportunity"]["stage"]

        @opportunity.reload
        assert_equal "qualified", @opportunity.stage
      end

      test "move_stage returns error for invalid stage" do
        post move_stage_api_v1_opportunity_path(@opportunity), params: {
          stage: "invalid_stage"
        }, headers: auth_headers, as: :json

        assert_response :unprocessable_entity

        response_body = JSON.parse(response.body)
        assert_equal false, response_body["success"]
      end

      test "move_stage requires authentication" do
        post move_stage_api_v1_opportunity_path(@opportunity), params: {
          stage: "qualified"
        }, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CLOSE_WON Tests
      # ====================================================================

      test "should close opportunity as won" do
        post close_won_api_v1_opportunity_path(@opportunity), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal "closed_won", response_body["opportunity"]["stage"]

        @opportunity.reload
        assert_equal "closed_won", @opportunity.stage
      end

      # ====================================================================
      # CLOSE_LOST Tests
      # ====================================================================

      test "should close opportunity as lost with reason" do
        post close_lost_api_v1_opportunity_path(@opportunity), params: {
          reason: "price"
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal "closed_lost", response_body["opportunity"]["stage"]

        @opportunity.reload
        assert_equal "closed_lost", @opportunity.stage
        assert_equal "price", @opportunity.lost_reason
      end

      test "close_lost requires reason" do
        post close_lost_api_v1_opportunity_path(@opportunity), headers: auth_headers, as: :json

        assert_response :unprocessable_entity

        response_body = JSON.parse(response.body)
        assert_equal false, response_body["success"]
      end

      # ====================================================================
      # REOPEN Tests
      # ====================================================================

      test "should reopen closed opportunity" do
        post reopen_api_v1_opportunity_path(@closed_opportunity), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]

        @closed_opportunity.reload
        assert_not_equal "closed_won", @closed_opportunity.stage
      end

      # ====================================================================
      # ASSIGN Tests
      # ====================================================================

      test "should assign opportunity to user" do
        another_user = users(:two)
        another_user.update!(entity: @entity)

        post assign_api_v1_opportunity_path(@opportunity), params: {
          user_id: another_user.id
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]

        @opportunity.reload
        assert_equal another_user.id, @opportunity.user_id
      end

      test "assign returns error without user_id or agent_id" do
        post assign_api_v1_opportunity_path(@opportunity), headers: auth_headers, as: :json

        assert_response :unprocessable_entity

        response_body = JSON.parse(response.body)
        assert_equal false, response_body["success"]
      end
    end
  end
end
