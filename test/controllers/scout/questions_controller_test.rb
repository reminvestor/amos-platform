# frozen_string_literal: true

require "test_helper"

module Scout
  class QuestionsControllerTest < ActionDispatch::IntegrationTest
    # Use fixtures for agent data to avoid foreign key issues
    fixtures :agent_plugins

    setup do
      @user = users(:one)
      @entity = entities(:one)
      @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

      # Use a fixture agent plugin or create one
      @agent_plugin = agent_plugins(:one) rescue AgentPlugin.find_or_create_by!(
        name: "Test Questions Agent",
        slug: "test_questions_agent",
        role: "executor",
        description: "A test agent for questions",
        status: "active",
        entity: @entity
      )

      # Ensure agent belongs to our entity
      @agent_plugin.update!(entity: @entity) unless @agent_plugin.entity == @entity

      # Create an execution
      @execution = AgentPluginExecution.create!(
        agent_plugin: @agent_plugin,
        user: @user,
        status: 'waiting_for_input'
      )

      # Create a pending question
      @question = AgentInputRequest.create!(
        agent_plugin_execution: @execution,
        question: "What is your preference?",
        status: "pending",
        priority: 1,
        session_id: "test_session_123"
      )
    end

    teardown do
      # Clean up test data
      AgentInputRequest.where(agent_plugin_execution_id: @execution&.id).delete_all
      @execution&.delete
    end

    # ====================================================================
    # Helper Methods
    # ====================================================================

    def auth_headers
      { "Authorization" => "Bearer #{@user.api_key}" }
    end

    # ====================================================================
    # PENDING (GET /amos/questions/pending) Tests
    # ====================================================================

    test "should get pending questions with valid token" do
      get amos_questions_pending_path,
        params: { session_id: "test_session_123" },
        headers: auth_headers,
        as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body["success"]
      assert response_body.key?("questions")
    end

    test "pending questions returns question data" do
      get amos_questions_pending_path,
        params: { session_id: "test_session_123" },
        headers: auth_headers,
        as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      questions = response_body["questions"]

      assert questions.any?
      question = questions.first
      assert question.key?("id")
      assert question.key?("question")
    end

    test "pending questions filters by session_id" do
      # Create question for different session
      other_execution = AgentPluginExecution.create!(
        agent_plugin: @agent_plugin,
        user: @user,
        status: 'waiting_for_input'
      )
      other_question = AgentInputRequest.create!(
        agent_plugin_execution: other_execution,
        question: "Other question?",
        status: "pending",
        session_id: "other_session"
      )

      get amos_questions_pending_path,
        params: { session_id: "test_session_123" },
        headers: auth_headers,
        as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      question_ids = response_body["questions"].map { |q| q["id"] }

      assert_includes question_ids, @question.id
      assert_not_includes question_ids, other_question.id

      # Cleanup
      other_question.delete
      other_execution.delete
    end

    test "pending questions requires authentication" do
      get amos_questions_pending_path,
        params: { session_id: "test_session_123" },
        as: :json

      assert_response :unauthorized
    end

    # ====================================================================
    # ANSWER (POST /amos/questions/:id/answer) Tests
    # ====================================================================

    test "should submit answer to question" do
      post "/amos/questions/#{@question.id}/answer",
        params: { answer: "My answer" },
        headers: auth_headers,
        as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body["success"]

      @question.reload
      assert_equal "answered", @question.status
    end

    test "answer question with empty answer" do
      post "/amos/questions/#{@question.id}/answer",
        params: { answer: "" },
        headers: auth_headers,
        as: :json

      # Should still succeed (empty answer is valid for skip scenarios)
      assert_includes [200, 422], response.status
    end

    test "answer question returns 404 for non-existent question" do
      post "/amos/questions/999999/answer",
        params: { answer: "My answer" },
        headers: auth_headers,
        as: :json

      assert_response :not_found
    end

    test "answer question requires authentication" do
      post "/amos/questions/#{@question.id}/answer",
        params: { answer: "My answer" },
        as: :json

      assert_response :unauthorized
    end

    # ====================================================================
    # SKIP (POST /amos/questions/:id/skip) Tests
    # ====================================================================

    test "should skip question" do
      post "/amos/questions/#{@question.id}/skip",
        params: { reason: "Not relevant" },
        headers: auth_headers,
        as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body["success"]

      @question.reload
      assert @question.skipped
    end

    test "skip question without reason" do
      post "/amos/questions/#{@question.id}/skip",
        params: {},
        headers: auth_headers,
        as: :json

      assert_response :success
    end

    test "skip question returns 404 for non-existent question" do
      post "/amos/questions/999999/skip",
        params: {},
        headers: auth_headers,
        as: :json

      assert_response :not_found
    end

    test "skip question requires authentication" do
      post "/amos/questions/#{@question.id}/skip",
        params: {},
        as: :json

      assert_response :unauthorized
    end
  end
end
