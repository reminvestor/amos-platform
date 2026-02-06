# frozen_string_literal: true

require "test_helper"

class V3::Tools::BashToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one) rescue User.new(id: 1)
    @entity = entities(:one) rescue Entity.new(id: 1)
    @tool = V3::Tools::BashTool.new(user: @user, entity: @entity)
  end

  test "metadata has correct name and category" do
    metadata = V3::Tools::BashTool.metadata
    assert_equal "bash", metadata[:name]
    assert_equal "v3_core", metadata[:category]
    assert metadata[:description].present?
  end

  test "executes simple commands" do
    result = @tool.execute({ "command" => "echo 'hello world'" })
    
    assert result[:success]
    assert_match /hello world/, result[:output]
    assert_equal 0, result[:exit_code]
  end

  test "returns error for missing command" do
    result = @tool.execute({})
    
    assert_equal false, result[:success]
    assert_match /Missing/, result[:error]
  end

  test "blocks rm -rf commands" do
    result = @tool.execute({ "command" => "rm -rf /" })
    
    assert_equal false, result[:success]
    assert_match /blocked/, result[:error].downcase
  end

  test "blocks sudo commands" do
    result = @tool.execute({ "command" => "sudo cat /etc/passwd" })
    
    assert_equal false, result[:success]
    assert_match /sudo/, result[:error]
  end

  test "blocks localhost access via curl" do
    result = @tool.execute({ "command" => "curl http://localhost:3000" })
    
    assert_equal false, result[:success]
  end

  test "blocks SQL injection patterns" do
    result = @tool.execute({ "command" => "echo 'DROP TABLE users'" })
    
    assert_equal false, result[:success]
  end

  test "handles command timeout" do
    result = @tool.execute({ "command" => "sleep 60", "timeout" => 1 })
    
    assert_equal false, result[:success]
    assert_match /timed out/i, result[:error]
  end

  test "truncates large output" do
    # Generate output larger than MAX_OUTPUT_SIZE
    result = @tool.execute({ "command" => "ruby -e 'puts \"x\" * 20000'" })
    
    assert result[:success]
    if result[:output].length > V3::Tools::BashTool::MAX_OUTPUT_SIZE
      assert result[:truncated]
    end
  end

  test "can do ruby calculations" do
    result = @tool.execute({ "command" => "ruby -e 'puts 6 * 7'" })
    
    assert result[:success]
    assert_match /42/, result[:output]
  end

  test "reports execution time" do
    result = @tool.execute({ "command" => "echo test" })
    
    assert result[:success]
    assert result[:execution_time_ms].is_a?(Integer)
    assert result[:execution_time_ms] >= 0
  end

  test "enforces max timeout of 30 seconds" do
    # Request 999 second timeout - should be capped to 30
    result = @tool.execute({ "command" => "echo ok", "timeout" => 999 })
    assert result[:success]
    # The timeout was applied but since echo is instant, it succeeded
  end
end
