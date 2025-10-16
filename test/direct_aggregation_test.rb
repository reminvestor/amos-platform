require "test_helper"

class DirectAggregationTest < ActiveSupport::TestCase
  fixtures :users, :entities

  setup do
    @user = users(:one)
    @entity = entities(:one)

    # Create test artifact
    sample_data = [
      { "plan" => "premium", "amount" => 99.99 },
      { "plan" => "basic", "amount" => 29.99 },
      { "plan" => "premium", "amount" => 99.99 }
    ]

    @artifact = Artifact.create!(
      entity: @entity,
      user: @user,
      name: "Direct Test Data",
      source: "test",
      schema: { "plan" => "string", "amount" => "float" },
      sample: sample_data,
      row_count: 3
    )
  end

  teardown do
    @artifact&.destroy
  end

  test "direct service call for group_by_field aggregation" do
    service = ScoutGenericToolsService.new(@user, @entity)
    result = service.execute_aggregate_artifact_data({
      "artifact_id" => @artifact.id,
      "operation" => "group_by_field",
      "field" => "plan",
      "aggregations" => [
        { "function" => "count", "field" => "plan" },
        { "function" => "sum", "field" => "amount", "alias" => "total" }
      ]
    })

    assert result[:success], "Direct call should succeed"
    assert_not_nil result[:data][:results], "Results should be present"
  end

  test "execute_tool_by_name for simple_stats aggregation" do
    service = ScoutGenericToolsService.new(@user, @entity)
    result = service.execute_tool_by_name("aggregate_artifact_data", {
      "artifact_id" => @artifact.id,
      "operation" => "simple_stats"
    })

    assert result[:success], "Tool execution should succeed"
    assert_not_nil result[:data][:results], "Stats results should be present"
  end
end
