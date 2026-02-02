# frozen_string_literal: true

require 'test_helper'

module Api
  module V1
    class ExternalAgentsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = @user.entity
        @api_key = @user.api_key
        
        # Create an external agent for testing
        @agent = ExternalAgentRegistration.create!(
          entity: @entity,
          operator: @user,
          agent_identifier: "test_agent_#{SecureRandom.hex(4)}",
          agent_name: "Test OpenClaw Agent",
          agent_platform: "openclaw",
          capabilities: { documentation: { confidence: 0.9 }, content: { confidence: 0.8 } },
          allowed_bounty_types: %w[documentation content],
          allowed_tools: %w[web_search read_file search_codebase],
          status: "active"
        )
        
        # Create a bounty for testing
        @bounty = Bounty.create!(
          entity: @entity,
          title: "Write API documentation",
          description: "Create documentation for the external agent API",
          bounty_type: "documentation",
          points: 100,
          status: "open"
        )
      end

      # ═══════════════════════════════════════════════════════════════════════
      # REGISTRATION TESTS (uses operator API key)
      # ═══════════════════════════════════════════════════════════════════════

      test "should register new agent with operator API key" do
        agent_data = {
          agent_identifier: "new_openclaw_#{SecureRandom.hex(4)}",
          agent_name: "My New Agent",
          agent_platform: "openclaw",
          capabilities: {
            "documentation" => { "description" => "Can write docs", "confidence" => 0.9 }
          }
        }

        post register_api_v1_external_agents_path,
             params: agent_data,
             headers: auth_headers(@api_key),
             as: :json

        assert_response :created
        json = JSON.parse(response.body)
        
        assert json["success"]
        assert_not_nil json["agent"]["api_key"]
        # Status may be "active" or "pending" depending on activation settings
        assert_includes %w[active pending], json["agent"]["status"]
        # allowed_bounty_types is set based on capabilities and trust level
        assert json["agent"]["allowed_bounty_types"].is_a?(Array)
      end

      test "should reject registration without auth" do
        post register_api_v1_external_agents_path,
             params: { agent_identifier: "test", agent_name: "Test" },
             as: :json

        assert_response :unauthorized
      end

      test "should reject duplicate agent identifier" do
        post register_api_v1_external_agents_path,
             params: {
               agent_identifier: @agent.agent_identifier,
               agent_name: "Duplicate Agent",
               agent_platform: "openclaw"
             },
             headers: auth_headers(@api_key),
             as: :json

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert_match /already registered/, json["error"]
      end

      test "should list operator's agents" do
        get api_v1_external_agents_path,
            headers: auth_headers(@api_key),
            as: :json

        assert_response :success
        json = JSON.parse(response.body)
        
        assert json["success"]
        assert_equal 1, json["agents"].length
        assert_equal @agent.agent_name, json["agents"][0]["agent_name"]
      end

      # ═══════════════════════════════════════════════════════════════════════
      # BOUNTY DISCOVERY TESTS (uses external agent API key)
      # ═══════════════════════════════════════════════════════════════════════

      test "should discover bounties with agent API key" do
        get bounties_api_v1_external_agents_path,
            headers: agent_auth_headers(@agent),
            as: :json

        assert_response :success
        json = JSON.parse(response.body)
        
        assert json["success"]
        assert json["bounties"].is_a?(Array)
        assert_not_nil json["meta"]["your_daily_remaining"]
      end

      test "should filter bounties by agent capabilities" do
        # Create a feature bounty (not in agent's allowed types)
        Bounty.create!(
          entity: @entity,
          title: "Build new feature",
          bounty_type: "feature",
          points: 500,
          status: "open"
        )

        get bounties_api_v1_external_agents_path,
            headers: agent_auth_headers(@agent),
            as: :json

        json = JSON.parse(response.body)
        
        # Should only see documentation bounty, not feature
        bounty_types = json["bounties"].map { |b| b["bounty_type"] }
        assert_includes bounty_types, "documentation"
        assert_not_includes bounty_types, "feature"
      end

      test "should reject bounty discovery without agent auth" do
        get bounties_api_v1_external_agents_path, as: :json
        
        assert_response :unauthorized
      end

      test "should reject bounty discovery with inactive agent" do
        @agent.suspend!(reason: "Testing")

        get bounties_api_v1_external_agents_path,
            headers: agent_auth_headers(@agent),
            as: :json

        # Either 401 (invalid/inactive key) or 403 (suspended) is acceptable
        assert_includes [401, 403], response.status
      end

      # ═══════════════════════════════════════════════════════════════════════
      # BOUNTY CLAIMING TESTS
      # ═══════════════════════════════════════════════════════════════════════

      test "should claim bounty" do
        post api_v1_external_agent_claim_bounty_path(bounty_id: @bounty.id),
             params: { approach: "I will write comprehensive documentation" },
             headers: agent_auth_headers(@agent),
             as: :json

        assert_response :created
        json = JSON.parse(response.body)
        
        assert json["success"]
        # Execution can be "in_progress" or "claimed" depending on implementation
        assert_includes %w[in_progress claimed], json["execution"]["status"]
        assert_not_nil json["execution"]["expires_at"]
        
        # Bounty should be claimed
        @bounty.reload
        assert_includes %w[in_progress claimed], @bounty.status
      end

      test "should reject claiming bounty outside allowed types" do
        feature_bounty = Bounty.create!(
          entity: @entity,
          title: "Build feature",
          bounty_type: "feature",
          points: 500,
          status: "open"
        )

        post api_v1_external_agent_claim_bounty_path(bounty_id: feature_bounty.id),
             params: { approach: "I'll try" },
             headers: agent_auth_headers(@agent),
             as: :json

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert_match /not in your allowed types/, json["error"]
      end

      test "should enforce daily limit" do
        # Set daily limit to 1 and create an execution
        @agent.update!(daily_bounty_limit: 1)
        ExternalAgentExecution.create!(
          external_agent_registration: @agent,
          bounty: @bounty,
          entity: @entity,
          status: "in_progress",
          started_at: Time.current
        )
        @agent.today_stats.update!(bounties_claimed: 1)

        # Create another bounty and try to claim
        bounty2 = Bounty.create!(
          entity: @entity,
          title: "Another task",
          bounty_type: "documentation",
          points: 50,
          status: "open"
        )

        post api_v1_external_agent_claim_bounty_path(bounty_id: bounty2.id),
             params: { approach: "I'll do it" },
             headers: agent_auth_headers(@agent),
             as: :json

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert_match /daily.*limit/i, json["error"]
      end

      # ═══════════════════════════════════════════════════════════════════════
      # TOOL EXECUTION TESTS
      # ═══════════════════════════════════════════════════════════════════════

      test "should execute allowed tool" do
        execution = create_execution

        post api_v1_external_agent_execute_tool_path(tool_name: "web_search"),
             params: {
               execution_id: execution.id,
               args: { query: "amos api documentation" }
             },
             headers: agent_auth_headers(@agent),
             as: :json

        assert_response :success
        json = JSON.parse(response.body)
        
        # May or may not succeed depending on tool, but should process
        assert_not_nil json["execution_log"]
        assert_not_nil json["execution_log"]["tool_calls_remaining"]
      end

      test "should reject disallowed tool" do
        execution = create_execution

        post api_v1_external_agent_execute_tool_path(tool_name: "delete_object"),
             params: {
               execution_id: execution.id,
               args: { id: 123 }
             },
             headers: agent_auth_headers(@agent),
             as: :json

        assert_response :forbidden
      end

      # ═══════════════════════════════════════════════════════════════════════
      # WORK SUBMISSION TESTS
      # ═══════════════════════════════════════════════════════════════════════

      test "should submit work" do
        execution = create_execution

        post api_v1_external_agent_submit_work_path(bounty_id: @bounty.id),
             params: {
               execution_id: execution.id,
               work_summary: "I created comprehensive API documentation",
               deliverables: {
                 content: "# API Documentation\n\n## Endpoints\n...",
                 format: "markdown"
               },
               work_log: "1. Researched API\n2. Wrote docs\n3. Added examples"
             },
             headers: agent_auth_headers(@agent),
             as: :json

        assert_response :success
        json = JSON.parse(response.body)
        
        assert json["success"]
        assert_equal "submitted", json["submission"]["status"]
        
        execution.reload
        assert_equal "submitted", execution.status
        assert_not_nil execution.submitted_at
      end

      test "should reject submission for expired execution" do
        execution = create_execution
        execution.update!(expires_at: 1.hour.ago)

        post api_v1_external_agent_submit_work_path(bounty_id: @bounty.id),
             params: {
               execution_id: execution.id,
               work_summary: "Done",
               deliverables: { content: "Work" }
             },
             headers: agent_auth_headers(@agent),
             as: :json

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert_match /expired/, json["error"]
      end

      # ═══════════════════════════════════════════════════════════════════════
      # STATUS TESTS
      # ═══════════════════════════════════════════════════════════════════════

      test "should get agent status" do
        get status_api_v1_external_agents_path,
            headers: agent_auth_headers(@agent),
            as: :json

        assert_response :success
        json = JSON.parse(response.body)
        
        assert_not_nil json["agent"]
        assert_equal @agent.agent_name, json["agent"]["agent_name"]
        assert_not_nil json["agent"]["reputation_score"]
        assert_not_nil json["agent"]["daily_remaining"]
      end

      private

      def auth_headers(api_key)
        { "Authorization" => "Bearer #{api_key}", "Content-Type" => "application/json" }
      end

      def agent_auth_headers(agent)
        { "Authorization" => "Bearer #{agent.api_key}", "Content-Type" => "application/json" }
      end

      def create_execution
        # Claim the bounty first
        @bounty.update!(status: "claimed", claimed_by: @user)
        
        ExternalAgentExecution.create!(
          external_agent_registration: @agent,
          bounty: @bounty,
          entity: @entity,
          status: "in_progress",
          started_at: Time.current,
          expires_at: 24.hours.from_now
        )
      end
    end
  end
end
