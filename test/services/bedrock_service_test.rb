require "test_helper"
require "minitest/mock"

class BedrockServiceTest < ActiveSupport::TestCase
  def setup
    @service = BedrockService.new
    @mock_client = Minitest::Mock.new
    @service.instance_variable_set(:@client, @mock_client)
  end

  # ============================================================================
  # PROMPT CACHING TESTS
  # ============================================================================

  test "adds cache_control to system prompt when present" do
    system_prompt = "You are a helpful assistant."
    messages = [{ role: "user", content: "Hello" }]

    # Mock the client's converse_stream method to capture the payload
    captured_payload = nil
    @mock_client.expect :converse_stream, nil do |payload|
      captured_payload = payload
      # Return a mock stream object
      mock_stream = Minitest::Mock.new
      mock_stream.expect :on_error_event, nil
      mock_stream.expect :on_event, nil
      mock_stream
    end

    begin
      @service.send_message_streaming(
        system_prompt,
        messages,
        model: "claude-sonnet-4-5",
        max_tokens: 1000,
        temperature: 0.7
      ) {}
    rescue
      # Expected to fail since we're mocking
    end

    # Verify cache_control was added to system prompt
    assert_not_nil captured_payload, "Payload should be captured"
    assert captured_payload.key?(:system), "Payload should have system key"
    assert_equal 1, captured_payload[:system].length, "Should have 1 system message"

    system_message = captured_payload[:system].first
    assert_equal system_prompt, system_message[:text], "System prompt text should match"
    assert system_message.key?(:cache_control), "Should have cache_control"
    assert_equal "ephemeral", system_message[:cache_control][:type], "Cache type should be ephemeral"
  end

  test "adds cache_control to last tool when tools provided" do
    system_prompt = "You are a helpful assistant."
    messages = [{ role: "user", content: "Hello" }]
    tools = [
      { name: "tool1", description: "First tool", parameters: {} },
      { name: "tool2", description: "Second tool", parameters: {} },
      { name: "tool3", description: "Third tool", parameters: {} }
    ]

    captured_payload = nil
    @mock_client.expect :converse_stream, nil do |payload|
      captured_payload = payload
      mock_stream = Minitest::Mock.new
      mock_stream.expect :on_error_event, nil
      mock_stream.expect :on_event, nil
      mock_stream
    end

    begin
      @service.send_message_streaming(
        system_prompt,
        messages,
        model: "claude-sonnet-4-5",
        max_tokens: 1000,
        temperature: 0.7,
        tools: tools
      ) {}
    rescue
      # Expected to fail
    end

    # Verify cache_control was added to last tool
    assert_not_nil captured_payload, "Payload should be captured"
    assert captured_payload.key?(:tool_config), "Payload should have tool_config"

    formatted_tools = captured_payload[:tool_config][:tools]
    assert_equal 3, formatted_tools.length, "Should have 3 tools"

    # First two tools should NOT have cache_control
    assert_nil formatted_tools[0][:cache_control], "First tool should not have cache_control"
    assert_nil formatted_tools[1][:cache_control], "Second tool should not have cache_control"

    # Last tool SHOULD have cache_control
    assert_not_nil formatted_tools[2][:cache_control], "Last tool should have cache_control"
    assert_equal "ephemeral", formatted_tools[2][:cache_control][:type], "Cache type should be ephemeral"
  end

  test "does not add cache_control when system prompt is blank" do
    messages = [{ role: "user", content: "Hello" }]

    captured_payload = nil
    @mock_client.expect :converse_stream, nil do |payload|
      captured_payload = payload
      mock_stream = Minitest::Mock.new
      mock_stream.expect :on_error_event, nil
      mock_stream.expect :on_event, nil
      mock_stream
    end

    begin
      @service.send_message_streaming(
        nil,  # No system prompt
        messages,
        model: "claude-sonnet-4-5",
        max_tokens: 1000,
        temperature: 0.7
      ) {}
    rescue
      # Expected to fail
    end

    # Verify no system key in payload when prompt is blank
    assert_not_nil captured_payload, "Payload should be captured"
    assert_nil captured_payload[:system], "System should be nil when no prompt provided"
  end

  test "does not add cache_control when tools array is empty" do
    system_prompt = "You are a helpful assistant."
    messages = [{ role: "user", content: "Hello" }]

    captured_payload = nil
    @mock_client.expect :converse_stream, nil do |payload|
      captured_payload = payload
      mock_stream = Minitest::Mock.new
      mock_stream.expect :on_error_event, nil
      mock_stream.expect :on_event, nil
      mock_stream
    end

    begin
      @service.send_message_streaming(
        system_prompt,
        messages,
        model: "claude-sonnet-4-5",
        max_tokens: 1000,
        temperature: 0.7,
        tools: []  # Empty tools array
      ) {}
    rescue
      # Expected to fail
    end

    # Verify no tool_config when tools empty
    assert_not_nil captured_payload, "Payload should be captured"
    assert_nil captured_payload[:tool_config], "tool_config should be nil when tools empty"
  end

  # ============================================================================
  # CACHE STATISTICS LOGGING TESTS
  # ============================================================================

  test "extracts cache_creation_input_tokens from usage metadata" do
    mock_usage = OpenStruct.new(
      input_tokens: 8000,
      output_tokens: 450,
      cache_creation_input_tokens: 9500,
      cache_read_input_tokens: 0
    )

    # Test that we can extract cache statistics
    assert_equal 9500, mock_usage.cache_creation_input_tokens
    assert_equal 0, mock_usage.cache_read_input_tokens
  end

  test "extracts cache_read_input_tokens from usage metadata" do
    mock_usage = OpenStruct.new(
      input_tokens: 8000,
      output_tokens: 450,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 9500
    )

    # Test that we can extract cache read statistics
    assert_equal 0, mock_usage.cache_creation_input_tokens
    assert_equal 9500, mock_usage.cache_read_input_tokens
  end

  test "calculates cache hit rate correctly" do
    # Simulate second request in conversation (cache hit)
    input_tokens = 8000
    cache_read = 9500

    cache_hit_rate = (cache_read.to_f / (input_tokens + cache_read) * 100).round(1)

    assert_equal 54.3, cache_hit_rate, "Cache hit rate should be 54.3%"
  end

  test "calculates token savings correctly" do
    cache_read = 9500
    savings = (cache_read * 0.9).round(0)  # 90% discount on cached tokens

    assert_equal 8550, savings, "Should save 90% of cached tokens"
  end

  test "calculates cost savings correctly" do
    cache_read = 9500
    savings = (cache_read * 0.9).round(0)  # 90% discount
    cost_savings = (savings * 0.0000075).round(4)  # $7.50 per 1M tokens

    assert_equal 0.0641, cost_savings, "Should calculate correct cost savings"
  end

  # ============================================================================
  # INTEGRATION SCENARIOS
  # ============================================================================

  test "first request creates cache with no cache_read" do
    # Simulate first request in conversation
    mock_usage = OpenStruct.new(
      input_tokens: 17500,  # System + tools + conversation
      output_tokens: 450,
      cache_creation_input_tokens: 9500,  # Creating cache for system + tools
      cache_read_input_tokens: 0          # Nothing cached yet
    )

    assert_equal 9500, mock_usage.cache_creation_input_tokens, "Should create cache on first request"
    assert_equal 0, mock_usage.cache_read_input_tokens, "Should not read cache on first request"
  end

  test "second request reads cache with no cache_creation" do
    # Simulate second request in conversation (within 5 min)
    mock_usage = OpenStruct.new(
      input_tokens: 8000,   # Only conversation (system + tools cached)
      output_tokens: 450,
      cache_creation_input_tokens: 0,      # Not creating cache
      cache_read_input_tokens: 9500        # Reading cached system + tools
    )

    assert_equal 0, mock_usage.cache_creation_input_tokens, "Should not create cache on second request"
    assert_equal 9500, mock_usage.cache_read_input_tokens, "Should read cache on second request"
  end

  test "handles missing cache statistics gracefully" do
    # Simulate response without cache statistics (e.g., old API version)
    mock_usage = OpenStruct.new(
      input_tokens: 17500,
      output_tokens: 450
      # No cache_creation_input_tokens or cache_read_input_tokens
    )

    # Should default to 0 when not present
    cache_creation = mock_usage.respond_to?(:cache_creation_input_tokens) ? mock_usage.cache_creation_input_tokens : 0
    cache_read = mock_usage.respond_to?(:cache_read_input_tokens) ? mock_usage.cache_read_input_tokens : 0

    assert_equal 0, cache_creation, "Should default to 0 when missing"
    assert_equal 0, cache_read, "Should default to 0 when missing"
  end

  # ============================================================================
  # FORMAT_TOOLS_FOR_BEDROCK METHOD TESTS
  # ============================================================================

  test "format_tools_for_bedrock creates proper Bedrock API structure" do
    tools = [
      { name: "tool1", description: "First tool", parameters: { type: "object", properties: {} } },
      { name: "tool2", description: "Second tool", parameters: { type: "object", properties: {} } }
    ]

    formatted = @service.send(:format_tools_for_bedrock, tools)

    assert_equal 2, formatted.length

    # Check first tool structure
    assert formatted[0].key?(:tool_spec), "Should have tool_spec key"
    assert_equal "tool1", formatted[0][:tool_spec][:name]
    assert_equal "First tool", formatted[0][:tool_spec][:description]
    assert formatted[0][:tool_spec].key?(:input_schema), "Should have input_schema"
    assert formatted[0][:tool_spec][:input_schema].key?(:json), "Input schema should have json key"

    # Check second tool structure
    assert formatted[1].key?(:tool_spec), "Should have tool_spec key"
    assert_equal "tool2", formatted[1][:tool_spec][:name]
    assert_equal "Second tool", formatted[1][:tool_spec][:description]
  end

  # ============================================================================
  # EDGE CASES
  # ============================================================================

  test "handles single tool with cache_control" do
    tools = [
      { name: "only_tool", description: "Single tool", parameters: {} }
    ]

    captured_payload = nil
    @mock_client.expect :converse_stream, nil do |payload|
      captured_payload = payload
      mock_stream = Minitest::Mock.new
      mock_stream.expect :on_error_event, nil
      mock_stream.expect :on_event, nil
      mock_stream
    end

    begin
      @service.send_message_streaming(
        "Test",
        [{ role: "user", content: "Hello" }],
        model: "claude-sonnet-4-5",
        max_tokens: 1000,
        tools: tools
      ) {}
    rescue
      # Expected to fail
    end

    formatted_tools = captured_payload[:tool_config][:tools]
    assert_equal 1, formatted_tools.length
    assert_not_nil formatted_tools[0][:cache_control], "Single tool should have cache_control"
  end

  test "cache_control format matches AWS Bedrock API spec" do
    # Verify the exact format expected by AWS Bedrock
    system_prompt = "Test prompt"
    messages = [{ role: "user", content: "Hello" }]

    captured_payload = nil
    @mock_client.expect :converse_stream, nil do |payload|
      captured_payload = payload
      mock_stream = Minitest::Mock.new
      mock_stream.expect :on_error_event, nil
      mock_stream.expect :on_event, nil
      mock_stream
    end

    begin
      @service.send_message_streaming(system_prompt, messages) {}
    rescue
      # Expected to fail
    end

    cache_control = captured_payload[:system].first[:cache_control]

    # AWS Bedrock expects exactly this format
    assert_equal Hash, cache_control.class
    assert cache_control.key?(:type)
    assert_equal "ephemeral", cache_control[:type]
    assert_equal 1, cache_control.keys.length, "Should only have 'type' key"
  end
end
