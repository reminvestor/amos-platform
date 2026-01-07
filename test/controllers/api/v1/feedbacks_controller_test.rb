# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class FeedbacksControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create ScoutMessages to use as feedbackables (separate for unique constraint)
        @session_id = SecureRandom.uuid
        @scout_message = ScoutMessage.create!(
          user: @user,
          entity: @entity,
          session_id: @session_id,
          role: "assistant",
          content: "Test assistant message"
        )

        @scout_message_2 = ScoutMessage.create!(
          user: @user,
          entity: @entity,
          session_id: @session_id,
          role: "assistant",
          content: "Second test message"
        )

        # Create test feedback (each on different feedbackable to avoid unique constraint)
        @positive_feedback = UserFeedback.create!(
          user: @user,
          entity: @entity,
          feedbackable: @scout_message,
          rating: 1,
          comment: "Great response!",
          feedback_type: "helpfulness",
          session_id: @session_id
        )

        @negative_feedback = UserFeedback.create!(
          user: @user,
          entity: @entity,
          feedbackable: @scout_message_2,
          rating: -1,
          comment: "Not helpful",
          feedback_type: "accuracy",
          session_id: @session_id
        )
      end

      teardown do
        UserFeedback.where(user: @user).destroy_all
        ScoutMessage.where(session_id: @session_id).destroy_all if @session_id
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

      test "should get feedbacks list with valid token" do
        get api_v1_feedbacks_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert response_body.key?("feedbacks")
        assert response_body.key?("pagination")
      end

      test "feedbacks list returns expected fields" do
        get api_v1_feedbacks_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        feedbacks = response_body["feedbacks"]

        assert feedbacks.any?

        feedback = feedbacks.find { |f| f["id"] == @positive_feedback.id }
        assert_not_nil feedback
        assert_equal 1, feedback["rating"]
        assert_equal "Great response!", feedback["comment"]
        assert_equal "helpfulness", feedback["feedback_type"]
        assert feedback.key?("rating_label")
        assert feedback.key?("rating_emoji")
        assert feedback.key?("feedbackable_type")
        assert feedback.key?("session_id")
        assert feedback.key?("created_at")
      end

      test "feedbacks list can filter by session" do
        get api_v1_feedbacks_path, params: { session_id: @scout_message.session_id }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        feedbacks = response_body["feedbacks"]

        feedbacks.each do |f|
          assert_equal @scout_message.session_id, f["session_id"]
        end
      end

      test "feedbacks list can filter by rating" do
        get api_v1_feedbacks_path, params: { rating: 1 }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        feedbacks = response_body["feedbacks"]

        feedbacks.each do |f|
          assert_equal 1, f["rating"]
        end
      end

      test "feedbacks list can filter by type" do
        get api_v1_feedbacks_path, params: { type: "ScoutMessage" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        feedbacks = response_body["feedbacks"]

        feedbacks.each do |f|
          assert_equal "ScoutMessage", f["feedbackable_type"]
        end
      end

      test "feedbacks list requires authentication" do
        get api_v1_feedbacks_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CREATE Tests
      # ====================================================================

      test "should create feedback with valid params" do
        new_message = ScoutMessage.create!(
          user: @user,
          entity: @entity,
          session_id: SecureRandom.uuid,
          role: "assistant",
          content: "Another message"
        )

        assert_difference("UserFeedback.count", 1) do
          post api_v1_feedbacks_path, params: {
            feedback: {
              feedbackable_type: "ScoutMessage",
              feedbackable_id: new_message.id,
              rating: 1,
              comment: "Very helpful!",
              feedback_type: "overall",
              session_id: new_message.session_id
            }
          }, headers: auth_headers, as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal 1, response_body["feedback"]["rating"]
        assert_equal "Very helpful!", response_body["feedback"]["comment"]
        assert response_body.key?("message")

        new_message.destroy
      end

      test "create returns appropriate message for positive feedback" do
        new_message = ScoutMessage.create!(
          user: @user,
          entity: @entity,
          session_id: SecureRandom.uuid,
          role: "assistant",
          content: "Another message"
        )

        post api_v1_feedbacks_path, params: {
          feedback: {
            feedbackable_type: "ScoutMessage",
            feedbackable_id: new_message.id,
            rating: 1
          }
        }, headers: auth_headers, as: :json

        assert_response :created

        response_body = JSON.parse(response.body)
        assert response_body["message"].include?("positive")

        new_message.destroy
      end

      test "create returns appropriate message for negative feedback" do
        new_message = ScoutMessage.create!(
          user: @user,
          entity: @entity,
          session_id: SecureRandom.uuid,
          role: "assistant",
          content: "Another message"
        )

        post api_v1_feedbacks_path, params: {
          feedback: {
            feedbackable_type: "ScoutMessage",
            feedbackable_id: new_message.id,
            rating: -1
          }
        }, headers: auth_headers, as: :json

        assert_response :created

        response_body = JSON.parse(response.body)
        assert response_body["message"].include?("better")

        new_message.destroy
      end

      test "create fails with invalid rating" do
        post api_v1_feedbacks_path, params: {
          feedback: {
            feedbackable_type: "ScoutMessage",
            feedbackable_id: @scout_message.id,
            rating: 5  # Invalid rating
          }
        }, headers: auth_headers, as: :json

        assert_response :unprocessable_entity

        response_body = JSON.parse(response.body)
        assert_equal false, response_body["success"]
        assert response_body.key?("errors")
      end

      test "create requires authentication" do
        post api_v1_feedbacks_path, params: {
          feedback: {
            feedbackable_type: "ScoutMessage",
            feedbackable_id: @scout_message.id,
            rating: 1
          }
        }, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # STATS Tests
      # ====================================================================

      test "should get feedback stats" do
        get stats_api_v1_feedbacks_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert response_body.key?("stats")

        stats = response_body["stats"]
        assert stats.key?("total")
        assert stats.key?("positive")
        assert stats.key?("negative")
        assert stats.key?("neutral")
        assert stats.key?("with_comments")
        assert stats.key?("satisfaction_score")
        assert stats.key?("by_type")
        assert stats.key?("daily_trend")
      end

      test "stats returns correct counts" do
        get stats_api_v1_feedbacks_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        stats = response_body["stats"]

        # We created 1 positive and 1 negative feedback
        assert stats["positive"] >= 1
        assert stats["negative"] >= 1
      end

      test "stats can filter by time range" do
        get stats_api_v1_feedbacks_path, params: { since: 7.days.ago.iso8601 }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("stats")
      end

      test "stats requires authentication" do
        get stats_api_v1_feedbacks_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should delete own feedback" do
        assert_difference("UserFeedback.count", -1) do
          delete api_v1_feedback_path(@positive_feedback), headers: auth_headers, as: :json
        end

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
      end

      test "destroy returns 404 for non-existent feedback" do
        delete api_v1_feedback_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "destroy requires authentication" do
        delete api_v1_feedback_path(@positive_feedback), as: :json

        assert_response :unauthorized
      end

      test "should not delete other user feedback" do
        other_user = users(:two)
        other_user.update!(entity: entities(:two), api_key: SecureRandom.hex(32))

        other_message = ScoutMessage.create!(
          user: other_user,
          entity: entities(:two),
          session_id: SecureRandom.uuid,
          role: "assistant",
          content: "Other user message"
        )

        other_feedback = UserFeedback.create!(
          user: other_user,
          entity: entities(:two),
          feedbackable: other_message,
          rating: 1
        )

        delete api_v1_feedback_path(other_feedback), headers: auth_headers, as: :json

        # Should not find the feedback (belongs to other user)
        assert_response :not_found

        # Verify it still exists
        assert UserFeedback.exists?(other_feedback.id)

        other_feedback.destroy
        other_message.destroy
      end
    end
  end
end
