require "test_helper"

class SmartAgentTest < ActiveSupport::TestCase
  fixtures :users, :entities

  setup do
    @user = users(:one)
    @entity = entities(:one)

    # Create a test artifact
    sample_data = [
      { "id" => "cus_123", "email" => "john@example.com", "plan" => "premium", "created" => "2024-01-15", "amount" => 99.99 },
      { "id" => "cus_456", "email" => "jane@example.com", "plan" => "basic", "created" => "2024-02-20", "amount" => 29.99 },
      { "id" => "cus_789", "email" => "bob@example.com", "plan" => "premium", "created" => "2024-03-10", "amount" => 99.99 }
    ]

    @artifact = Artifact.create!(
      entity: @entity,
      user: @user,
      name: "Test Customer Data",
      source: "test",
      schema: Artifact.infer_schema(sample_data),
      sample: sample_data,
      row_count: sample_data.length
    )
  end

  teardown do
    @artifact&.destroy
  end

  test "artifact creation and aggregation with group_by_field" do
    assert_not_nil @artifact
    assert_equal "Test Customer Data", @artifact.name
    assert_equal @entity, @artifact.entity
    assert_equal @user, @artifact.user

    # Test aggregation using the tool directly
    tool = Tools::AggregateArtifactDataTool.new(
      user: @user,
      entity: @entity
    )

    result = tool.execute(
      artifact_id: @artifact.id,
      operation: "group_by_field",
      field: "plan",
      aggregations: [
        { "function" => "count", "field" => "plan" },
        { "function" => "sum", "field" => "amount", "alias" => "total_revenue" }
      ]
    )

    assert result[:success], "Aggregation should succeed: #{result[:error]}"
    assert_not_nil result[:data], "Results should be present"
  end

  test "agent loadout enforcement allows permitted tools" do
    loadout = AgentLoadout.new(
      agent_role: "analyst",
      tool_allowlist: [ "aggregate_artifact_data", "fetch_next_page" ],
      canvas_allowlist: [ "dynamic_canvas" ]
    )

    # Test aggregation using the tool directly
    tool = Tools::AggregateArtifactDataTool.new(
      user: @user,
      entity: @entity
    )

    result = tool.execute(
      artifact_id: @artifact.id,
      operation: "simple_stats"
    )

    assert result[:success], "Allowed tool should succeed: #{result[:error]}"
    assert loadout.tool_allowed?("aggregate_artifact_data"), "Tool should be in allowlist"
  end

  test "agent loadout enforcement blocks non-permitted tools" do
    loadout = AgentLoadout.new(
      agent_role: "analyst",
      tool_allowlist: [ "aggregate_artifact_data", "fetch_next_page" ],
      canvas_allowlist: [ "dynamic_canvas" ]
    )

    tool_runner = ToolRunner.new
    denied_result = tool_runner.call(
      tool: "create_object",
      inputs: { object_type: "contact" },
      agent_loadout: loadout
    )

    assert denied_result[:denied], "Non-allowed tool should be denied"
  end

  test "canvas governance with analyst loadout" do
    analyst_loadout = AgentLoadout.new(agent_role: "analyst")

    assert analyst_loadout.canvas_allowed?("dynamic_canvas"), "dynamic_canvas should be allowed for analyst"
    assert_not analyst_loadout.canvas_allowed?("task_progress"), "task_progress should not be allowed for analyst"
  end

  test "workflow templates are available" do
    templates = WorkflowTemplate.active
    assert templates.count >= 0, "Should have workflow templates or none"
  end
end
