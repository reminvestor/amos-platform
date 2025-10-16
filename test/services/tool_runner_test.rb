require "test_helper"

class ToolRunnerTest < ActiveSupport::TestCase
  fixtures :users, :entities
  def setup
    @tool_runner = ToolRunner.new
  end

  def test_successful_tool_execution
    result = @tool_runner.call(
      tool: "create_contact",
      inputs: {
        email: "test@example.com",
        first_name: "John",
        last_name: "Doe"
      }
    )

    assert_equal "success", result[:status]
    assert result[:data][:contact_id]
    assert_equal "create_contact", result[:tool]
    assert result[:idempotency_key]
  end

  def test_input_validation_failure
    result = @tool_runner.call(
      tool: "create_contact",
      inputs: {
        # Missing required email field
        first_name: "John"
      }
    )

    assert_equal "failed", result[:status]
    assert result[:error].include?("Invalid inputs")
    assert result[:validation_errors]
  end

  def test_unknown_tool
    result = @tool_runner.call(
      tool: "nonexistent_tool",
      inputs: {}
    )

    assert_equal "failed", result[:status]
    assert result[:error].include?("Unknown tool")
  end

  def test_landing_page_generation
    result = @tool_runner.call(
      tool: "generate_landing_page_dsl",
      inputs: {
        business_info: {
          business_name: "Test Consulting",
          industry: "Consulting",
          target_audience: "Small business owners"
        },
        design_preferences: {
          theme: "professional"
        }
      }
    )

    if result[:status] != "success"
      puts "Landing page generation failed: #{result[:error]}"
      puts "Validation errors: #{result[:validation_errors]}" if result[:validation_errors]
    end

    assert_equal "success", result[:status]
    assert result[:data][:dsl]
    assert_equal "Test Consulting", result[:data][:business_info][:business_name]
  end

  def test_landing_page_compilation
    sample_dsl = {
      page: {
        theme: "clean",
        sections: [
          {
            type: "hero",
            headline: "Test Page"
          }
        ]
      }
    }

    result = @tool_runner.call(
      tool: "compile_landing_page_html",
      inputs: {
        dsl: sample_dsl,
        slug: "test-page"
      }
    )

    if result[:status] != "success"
      puts "Landing page compilation failed: #{result[:error]}"
      puts "Validation errors: #{result[:validation_errors]}" if result[:validation_errors]
    end

    assert_equal "success", result[:status]
    assert result[:data][:html]
    assert result[:data][:html].include?("Test Page")
    assert result[:data][:html].include?("<!DOCTYPE html>")
  end

  def test_idempotency
    inputs = {
      email: "test@example.com",
      first_name: "John",
      last_name: "Doe"
    }

    idempotency_key = "test-key-123"

    # First call
    result1 = @tool_runner.call(
      tool: "create_contact",
      inputs: inputs,
      idempotency_key: idempotency_key
    )

    # Second call with same key should return cached result
    result2 = @tool_runner.call(
      tool: "create_contact",
      inputs: inputs,
      idempotency_key: idempotency_key
    )

    assert_equal result1[:data][:contact_id], result2[:data][:contact_id]
  end

  def test_tool_registry_info
    info = ToolRegistry.tool_info("create_contact")

    assert_equal "create_contact", info[:name]
    assert_equal "1.0", info[:version]
    assert info[:description].include?("contact")
    assert info[:input_schema]
    assert info[:output_schema]
  end

  def test_available_tools
    tools = ToolRegistry.available_tools

    assert tools.include?("create_contact")
    assert tools.include?("generate_landing_page_dsl")
    assert tools.include?("compile_landing_page_html")
  end

  def test_tools_by_category
    categories = ToolRegistry.tools_by_category

    assert categories["Content Generation"].include?("generate_landing_page_dsl")
    assert categories["Data Management"].include?("create_contact")
    assert categories["Content Processing"].include?("compile_landing_page_html")
  end
end
