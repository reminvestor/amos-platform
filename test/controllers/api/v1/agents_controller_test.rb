require "test_helper"

module Api
  module V1
    class AgentsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create test agent plugins with unique slugs
        @test_slug_suffix = SecureRandom.hex(4)
        @agent = AgentPlugin.create!(
          name: "Test Agent",
          slug: "test_agent_#{@test_slug_suffix}",
          role: "executor",
          description: "A test agent for testing",
          status: "active",
          entity: @entity,
          execution_strategy: "standard",
          configuration: { interactive: true, fields: [] }
        )

        @inactive_agent = AgentPlugin.create!(
          name: "Inactive Agent",
          slug: "inactive_agent_#{@test_slug_suffix}",
          role: "executor",
          description: "An inactive agent",
          status: "draft",
          entity: @entity,
          execution_strategy: "standard"
        )

        @system_agent = AgentPlugin.create!(
          name: "System Agent",
          slug: "system_agent_#{@test_slug_suffix}",
          role: "planner",
          description: "A system-wide agent",
          status: "active",
          entity: nil,  # System-wide agent
          execution_strategy: "standard"
        )
      end

      teardown do
        AgentPlugin.where("slug LIKE ?", "%_#{@test_slug_suffix}").destroy_all if @test_slug_suffix
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

      test "should get agents list with valid token" do
        get api_v1_agents_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("agents")
        assert response_body.key?("total")
      end

      test "agents list returns expected fields" do
        get api_v1_agents_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        agents = response_body["agents"]

        assert agents.any?

        agent = agents.find { |a| a["id"] == @agent.id }
        assert_not_nil agent
        assert_equal @agent.name, agent["name"]
        assert_equal @agent.description, agent["description"]
        assert_equal @agent.role, agent["agent_type"]
        assert agent.key?("icon")
        assert agent.key?("created_at")
      end

      test "agents list only returns active agents" do
        get api_v1_agents_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        agent_ids = response_body["agents"].map { |a| a["id"] }

        assert_includes agent_ids, @agent.id
        assert_not_includes agent_ids, @inactive_agent.id
      end

      test "agents list includes system-wide agents" do
        get api_v1_agents_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        agent_ids = response_body["agents"].map { |a| a["id"] }

        assert_includes agent_ids, @system_agent.id
      end

      test "agents list does not include other entity agents" do
        # Use entities(:two) from fixtures - it's a different entity
        other_entity = entities(:two)

        other_agent = AgentPlugin.create!(
          name: "Other Entity Agent Test",
          slug: "other_entity_agent_test_#{SecureRandom.hex(4)}",
          role: "executor",
          description: "An agent from another entity",
          status: "active",
          entity: other_entity,
          execution_strategy: "standard"
        )

        get api_v1_agents_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        agent_ids = response_body["agents"].map { |a| a["id"] }

        assert_not_includes agent_ids, other_agent.id
        # No cleanup needed - tests use transactions that rollback
      end

      test "agents list requires authentication" do
        get api_v1_agents_path, as: :json

        assert_response :unauthorized
      end

      test "agents list rejects invalid token" do
        get api_v1_agents_path,
          headers: { "Authorization" => "Bearer invalid_token" },
          as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get agent details with valid token" do
        get api_v1_agent_path(@agent), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @agent.id, response_body["id"]
        assert_equal @agent.name, response_body["name"]
        assert_equal @agent.description, response_body["description"]
        assert_equal @agent.role, response_body["agent_type"]
      end

      test "agent details include capabilities and fields" do
        get api_v1_agent_path(@agent), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("capabilities")
        assert response_body.key?("fields")
        assert response_body.key?("interactive")
      end

      test "should return 404 for non-existent agent" do
        get api_v1_agent_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "should return 404 for inactive agent" do
        get api_v1_agent_path(@inactive_agent), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "agent show requires authentication" do
        get api_v1_agent_path(@agent), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # AGENT TYPES Tests
      # ====================================================================

      test "should get agent types" do
        get agent_types_api_v1_agents_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("types")
        assert response_body["types"].is_a?(Array)

        type_keys = response_body["types"].map { |t| t["key"] }
        assert_includes type_keys, "executor"
        assert_includes type_keys, "planner"
        assert_includes type_keys, "analyst"
      end

      # ====================================================================
      # ICON MAPPING Tests
      # ====================================================================

      test "executor role returns correct icon" do
        executor_agent = AgentPlugin.create!(
          name: "Executor Test",
          slug: "executor_test_#{SecureRandom.hex(4)}",
          role: "executor",
          status: "active",
          entity: @entity,
          execution_strategy: "standard"
        )

        get api_v1_agents_path, headers: auth_headers, as: :json

        response_body = JSON.parse(response.body)
        agent = response_body["agents"].find { |a| a["id"] == executor_agent.id }

        assert_equal "play-circle", agent["icon"]

        executor_agent.destroy
      end

      test "planner role returns correct icon" do
        get api_v1_agents_path, headers: auth_headers, as: :json

        response_body = JSON.parse(response.body)
        agent = response_body["agents"].find { |a| a["id"] == @system_agent.id }

        assert_equal "clipboard-list", agent["icon"]
      end
    end
  end
end
