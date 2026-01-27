require "test_helper"
require "rake"

class AgentLightningRakeTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)

    @entity.create_agent_lightning_config!(
      enabled: true,
      mode: "optimizing",
      training_strategy: "prompt_optimization",
      min_traces_for_training: 2
    ) unless @entity.agent_lightning_config

    # Load the rake file
    Rails.application.load_tasks
  end

  test "agent_lightning:status task outputs entity information" do
    output = capture_output do
      Rake::Task["agent_lightning:status"].invoke(@entity.id.to_s)
    end

    assert_includes output, "AGENT LIGHTNING STATUS"
    assert_includes output, @entity.name
    assert_includes output, "CONFIGURATION"
  end

  test "agent_lightning:status shows trace data" do
    # Create some traces
    2.times do
      lightning_store = LightningStoreService.new(@entity, @user)
      trace = lightning_store.start_workflow_trace(
        workflow_executions(:one),
        task_sessions(:one),
        "test"
      )
      lightning_store.record_llm_call(
        model: "claude-sonnet-4-5",
        agent_role: "executor",
        system_prompt: {},
        user_messages: [],
        response_content: {},
        input_tokens: 100,
        output_tokens: 50,
        latency_ms: 1000
      )
      lightning_store.record_reward(reward_type: "completion", reward_value: 0.8, source: "automated")
      lightning_store.complete_trace(output_data: { result: "success" })
    end

    output = capture_output do
      Rake::Task["agent_lightning:status"].invoke(@entity.id.to_s)
    end

    assert_includes output, "TRACE DATA"
    assert_includes output, "Total Traces"
  end

  test "agent_lightning:train task executes training" do
    # Create minimum traces for training
    2.times do
      lightning_store = LightningStoreService.new(@entity, @user)
      trace = lightning_store.start_workflow_trace(
        workflow_executions(:one),
        task_sessions(:one),
        "test"
      )
      lightning_store.record_llm_call(
        model: "claude-sonnet-4-5",
        agent_role: "executor",
        system_prompt: {},
        user_messages: [],
        response_content: {},
        input_tokens: 100,
        output_tokens: 50,
        latency_ms: 1000
      )
      lightning_store.record_reward(reward_type: "completion", reward_value: 0.8, source: "automated")
      lightning_store.complete_trace(output_data: { result: "success" })
    end

    output = capture_output do
      Rake::Task["agent_lightning:train"].invoke(@entity.id.to_s)
    end

    assert_includes output, "Starting Agent Lightning training"
  end

  test "agent_lightning:metrics task shows metrics" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      workflow_executions(:one),
      task_sessions(:one),
      "test"
    )
    lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 100,
      output_tokens: 50,
      latency_ms: 1000
    )
    lightning_store.complete_trace(output_data: { result: "success" })

    output = capture_output do
      Rake::Task["agent_lightning:metrics"].invoke(@entity.id.to_s)
    end

    assert_includes output, "AGENT LIGHTNING METRICS"
  end

  test "agent_lightning:export_training_data exports traces" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      workflow_executions(:one),
      task_sessions(:one),
      "test"
    )
    lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 100,
      output_tokens: 50,
      latency_ms: 1000
    )
    lightning_store.complete_trace(output_data: { result: "success" })

    # Clean up any existing export files
    Dir.glob("agent_lightning_training_data_*.json").each { |f| File.delete(f) }

    output = capture_output do
      Rake::Task["agent_lightning:export_training_data"].invoke(@entity.id.to_s)
    end

    assert_includes output, "Exporting Agent Lightning training data"
    assert_includes output, "Exported"

    # Clean up
    Dir.glob("agent_lightning_training_data_*.json").each { |f| File.delete(f) }
  end

  test "agent_lightning:setup_entity creates configuration" do
    # Create fresh entity without config
    new_entity = Entity.create!(name: "Test Entity")

    output = capture_output do
      Rake::Task["agent_lightning:setup_entity"].invoke(new_entity.id.to_s)
    end

    assert_includes output, "AGENT LIGHTNING SETUP"
    assert_includes output, "configured successfully"

    assert new_entity.reload.agent_lightning_config.present?
  end

  test "agent_lightning:cleanup removes old traces" do
    # Create old trace
    old_trace = AgentLightningTrace.create!(
      entity: @entity,
      user: @user,
      trace_type: "workflow",
      status: "completed",
      input_data: {},
      output_data: {},
      created_at: 100.days.ago
    )

    # Create recent trace
    recent_trace = AgentLightningTrace.create!(
      entity: @entity,
      user: @user,
      trace_type: "workflow",
      status: "completed",
      input_data: {},
      output_data: {},
      created_at: 30.days.ago
    )

    output = capture_output do
      Rake::Task["agent_lightning:cleanup"].invoke("90")
    end

    assert_includes output, "Cleaning up Agent Lightning traces"
    assert_not AgentLightningTrace.exists?(old_trace.id)
    assert AgentLightningTrace.exists?(recent_trace.id)
  end

  test "rake task fails gracefully with invalid entity" do
    output = capture_output do
      Rake::Task["agent_lightning:status"].invoke("invalid_id")
    end

    # Should handle the error gracefully
  end

  private

  def capture_output
    previous_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = previous_stdout
    # Clear task for next invocation
    Rake::Task.clear
    Rails.application.load_tasks
  end
end
