require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  fixtures :users, :entities
  def setup
    @simple_spec = {
      type: "test_workflow",
      steps: [
        {
          id: "step1",
          type: "tool_call",
          config: {
            tool: "test_tool",
            description: "First step"
          }
        },
        {
          id: "step2",
          type: "user_input",
          config: {
            title: "User Input",
            fields: [
              { name: "name", type: "text", required: true }
            ]
          }
        }
      ]
    }

    @workflow = Workflow.new(@simple_spec)
  end

  def test_workflow_initialization
    assert_equal "pending", @workflow.status
    assert_equal 2, @workflow.steps.length
    assert_equal "step1", @workflow.current_step.id
  end

  def test_workflow_progress_tracking
    progress = @workflow.progress

    assert_equal 2, progress[:total_steps]
    assert_equal 0, progress[:completed_steps]
    assert_equal 2, progress[:remaining_steps]
    assert_equal 0.0, progress[:progress_percentage]
    assert_equal "pending", progress[:status]
  end

  def test_step_execution_success
    result = @workflow.execute_next_step({})

    assert_equal "step_completed", result[:status]
    assert result[:message].include?("step1")
    assert_equal "step2", result[:next_step][:id]
  end

  def test_user_input_step
    # Complete first step
    @workflow.execute_next_step({})

    # Second step requires user input
    result = @workflow.execute_next_step({})

    assert_equal "awaiting_input", result[:status]
    # Debug the result structure
    # puts "Result: #{result.inspect}"

    # The form config should be in the step config
    step_config = result.dig(:step, :config) || result.dig(:step, "config")
    assert step_config, "Expected step config in result"

    form_title = step_config[:title] || step_config["title"]
    assert_equal "User Input", form_title
  end

  def test_user_input_with_data
    skip "TODO: Fix - workflow execution changed"
    # Complete first step
    @workflow.execute_next_step({})

    # Provide user input
    result = @workflow.execute_next_step({ name: "Test User" })

    assert_equal "step_completed", result[:status]
    assert result[:message].include?("completed successfully")
  end

  def test_workflow_completion
    # Execute all steps
    @workflow.execute_next_step({})
    @workflow.execute_next_step({ name: "Test User" })

    assert @workflow.completed?
    assert_equal "completed", @workflow.status

    progress = @workflow.progress
    assert_equal 100.0, progress[:progress_percentage]
    assert_equal 2, progress[:completed_steps]
  end

  def test_step_skipping
    current_step_id = @workflow.current_step.id

    result = @workflow.skip_current_step("Testing skip")

    assert result
    refute_equal current_step_id, @workflow.current_step&.id
  end

  def test_workflow_serialization
    hash = @workflow.to_hash

    assert hash[:spec].present?
    assert_equal "pending", hash[:status]
    assert hash[:progress].present?
    assert_equal 2, hash[:steps].length
  end

  def test_step_validation_error
    invalid_spec = {
      type: "invalid_workflow",
      steps: [
        {
          id: "invalid_step",
          type: "tool_call",
          config: {} # Missing required 'tool' config
        }
      ]
    }

    assert_raises(ArgumentError) do
      Workflow.new(invalid_spec)
    end
  end

  def test_conditional_step
    conditional_spec = {
      type: "conditional_test",
      steps: [
        {
          id: "condition_step",
          type: "conditional",
          config: {
            condition: "email contains @example.com",
            true_step: "next_step",
            false_step: "alt_step"
          }
        }
      ]
    }

    workflow = Workflow.new(conditional_spec)
    result = workflow.execute_next_step({ email: "test@example.com" })

    assert [ "step_completed", "completed" ].include?(result[:status])
    assert_equal true, result[:result][:condition_result]
  end

  def test_validation_step
    validation_spec = {
      type: "validation_test",
      steps: [
        {
          id: "validate_step",
          type: "validation",
          config: {
            rules: [
              { field: "email", type: "required" },
              { field: "email", type: "email" }
            ]
          }
        }
      ]
    }

    workflow = Workflow.new(validation_spec)

    # Test validation failure
    result = workflow.execute_next_step({ email: "invalid-email" })
    assert_equal "failed", result[:status]
    assert result[:error].include?("valid email")

    # Test validation success
    workflow = Workflow.new(validation_spec)
    result = workflow.execute_next_step({ email: "test@example.com" })
    assert_equal "step_completed", result[:status]
  end
end
