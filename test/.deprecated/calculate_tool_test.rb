# frozen_string_literal: true

require "test_helper"

class CalculateToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::CalculateTool.new(entity: @entity, user: @user)
  end

  test "metadata returns correct structure" do
    metadata = Tools::CalculateTool.metadata

    assert_equal "calculate", metadata[:name]
    assert_equal "utility", metadata[:category]
    assert metadata[:description].include?("mathematical")
  end

  test "is read only" do
    assert Tools::CalculateTool.read_only?
  end

  # Basic arithmetic tests
  test "evaluates simple addition" do
    result = @tool.execute({ expression: "175 + 138 + 103" })

    assert result[:success]
    assert_equal 416, result[:result]
  end

  test "evaluates subtraction" do
    result = @tool.execute({ expression: "500 - 150" })

    assert result[:success]
    assert_equal 350, result[:result]
  end

  test "evaluates multiplication" do
    result = @tool.execute({ expression: "25 * 4" })

    assert result[:success]
    assert_equal 100, result[:result]
  end

  test "evaluates division" do
    result = @tool.execute({ expression: "100 / 4" })

    assert result[:success]
    assert_equal 25.0, result[:result]
  end

  test "evaluates complex expression with parentheses" do
    result = @tool.execute({ expression: "(100 + 50) * 2 - 50" })

    assert result[:success]
    assert_equal 250, result[:result]
  end

  test "handles decimal precision" do
    result = @tool.execute({ expression: "10 / 3", precision: 4 })

    assert result[:success]
    assert_equal 3.3333, result[:result]
  end

  # Array operation tests
  test "calculates sum of values" do
    result = @tool.execute({ 
      values: [175, 188, 155, 305, 160, 168, 170],
      operation: "sum" 
    })

    assert result[:success]
    assert_equal 1321, result[:result]
  end

  test "calculates average of values" do
    result = @tool.execute({ 
      values: [100, 200, 300],
      operation: "avg" 
    })

    assert result[:success]
    assert_equal 200.0, result[:result]
  end

  test "finds minimum value" do
    result = @tool.execute({ 
      values: [175, 80, 200, 150],
      operation: "min" 
    })

    assert result[:success]
    assert_equal 80, result[:result]
  end

  test "finds maximum value" do
    result = @tool.execute({ 
      values: [175, 80, 200, 150],
      operation: "max" 
    })

    assert result[:success]
    assert_equal 200, result[:result]
  end

  test "counts values" do
    result = @tool.execute({ 
      values: [1, 2, 3, 4, 5],
      operation: "count" 
    })

    assert result[:success]
    assert_equal 5, result[:result]
  end

  test "calculates median of odd count" do
    result = @tool.execute({ 
      values: [1, 3, 5, 7, 9],
      operation: "median" 
    })

    assert result[:success]
    assert_equal 5, result[:result]
  end

  test "calculates median of even count" do
    result = @tool.execute({ 
      values: [1, 2, 3, 4],
      operation: "median" 
    })

    assert result[:success]
    assert_equal 2.5, result[:result]
  end

  test "calculates range" do
    result = @tool.execute({ 
      values: [10, 50, 30, 80],
      operation: "range" 
    })

    assert result[:success]
    assert_equal 70, result[:result]
  end

  # Error handling tests
  test "handles division by zero" do
    result = @tool.execute({ expression: "100 / 0" })

    assert_not result[:success]
    # With float division, 100.0/0 returns Infinity, so we check for that error message
    assert result[:error].include?("infinite") || result[:error].include?("Division by zero")
  end

  test "rejects dangerous code" do
    result = @tool.execute({ expression: "system('ls')" })

    assert_not result[:success]
    assert_includes result[:error], "disallowed"
  end

  test "rejects eval attempts" do
    result = @tool.execute({ expression: "eval('1+1')" })

    assert_not result[:success]
    assert_includes result[:error], "disallowed"
  end

  test "rejects backticks" do
    result = @tool.execute({ expression: "`ls`" })

    assert_not result[:success]
    assert_includes result[:error], "disallowed"
  end

  test "rejects file operations" do
    result = @tool.execute({ expression: "File.read('/etc/passwd')" })

    assert_not result[:success]
    assert_includes result[:error], "disallowed"
  end

  test "returns error when no expression or values provided" do
    result = @tool.execute({})

    assert_not result[:success]
    assert_includes result[:error], "provide either"
  end

  test "returns error for unknown array operation" do
    result = @tool.execute({ values: [1, 2, 3], operation: "invalid_op" })

    assert_not result[:success]
    assert_includes result[:error], "Unknown operation"
  end

  # Real-world scenario test (from the user's screenshot)
  test "correctly sums job costs from spreadsheet data" do
    # Simulating what should happen with the actual Excel data
    job_costs = [175.00, 188.00, 155.00, 305.00, 160.00, 168.00, 170.00, 
                 210.00, 148.00, 192.00, 185.00, 144.00, 140.00, 138.00,
                 135.00, 129.00, 198.00, 134.00, 142.00, 136.00, 105.00,
                 131.00, 132.00, 119.00, 118.00, 80.00, 112.00, 116.00,
                 113.00, 115.00, 112.00, 114.00, 169.00]

    result = @tool.execute({ values: job_costs, operation: "sum" })

    assert result[:success]
    # The correct total of the test data: 4888.0
    assert_equal 4888.0, result[:result]
    assert_equal 33, result[:value_count]
  end

  # Format number tests
  test "formats numbers with commas" do
    result = @tool.execute({ values: [1000000], operation: "sum" })

    assert result[:success]
    assert_equal "1,000,000", result[:formatted]
  end

  test "formats decimal numbers correctly" do
    result = @tool.execute({ expression: "1000.55 + 2000.45" })

    assert result[:success]
    assert_equal "3,001", result[:formatted]
  end
end
