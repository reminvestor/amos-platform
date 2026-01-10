# Agent Lightning Integration Guide

## Overview

This document describes the Agent Lightning integration for Scout Chat - an advanced reinforcement learning (RL) system for optimizing AI agent behavior and improving response quality over time without requiring code changes.

Agent Lightning enables the Scout platform to:
- **Learn from executions**: Collect traces of all agent actions (LLM calls, tool usage, workflow execution)
- **Optimize prompts**: Automatically improve system prompts and instructions based on success patterns
- **Implement RL training**: Train agents using hierarchical RL with credit assignment
- **Track performance**: Monitor improvements in token efficiency, success rates, and user satisfaction

## Architecture

### Components

#### 1. **LightningStore** (`app/services/lightning_store_service.rb`)
Central service for collecting and managing training data.

```ruby
# Start recording a workflow execution
lightning_store = LightningStoreService.new(entity, user)
trace = lightning_store.start_workflow_trace(workflow_execution, task_session, request_text)

# Record LLM calls
lightning_store.record_llm_call(
  model: "claude-sonnet-4-5",
  agent_role: "planner",
  system_prompt: prompt,
  user_messages: messages,
  response_content: response,
  input_tokens: 1000,
  output_tokens: 500,
  latency_ms: 1200
)

# Record tool executions
lightning_store.record_tool_execution(
  tool_name: "generate_ai_landing_page",
  tool_category: "content_generation",
  input_arguments: { title: "My App" },
  output_result: { page_id: "123", success: true },
  execution_time_ms: 5000
)

# Complete and record reward
lightning_store.complete_trace(output_data: { result: "success" })
lightning_store.record_reward(
  reward_type: "completion",
  reward_value: 0.85,
  source: "automated"
)
```

#### 2. **Database Models** (`app/models/agent_lightning_*.rb`)

**Core Models:**
- `AgentLightningTrace` - Main execution trace record
- `AgentLLMCall` - Individual LLM call tracking
- `AgentToolExecution` - Tool invocation and result tracking
- `AgentPhaseExecution` - Workflow phase execution tracking
- `AgentReward` - Training reward signals
- `AgentTrainingJob` - Training execution history
- `AgentLightningConfig` - Entity-level configuration

**Schema:**
```
AgentLightningTrace
├─ trace_id (uuid, unique)
├─ trace_type (workflow, llm_call, tool_execution)
├─ status (pending, completed, failed)
├─ input_data (jsonb)
├─ output_data (jsonb)
├─ intermediate_steps (array)
├─ token_count (integer)
├─ cost_estimate (decimal)
├─ duration_ms (integer)
├─ reward_signal (decimal, 0-1)
└─ metadata (jsonb)
```

#### 3. **Instrumentation** (`app/services/bedrock_service.rb`)

BedrockService automatically records LLM calls when:
- Entity and user are available
- Agent Lightning is enabled
- Request completes (success or error)

```ruby
# Automatic instrumentation points:
BedrockService#send_message_non_streaming
  ├─ Record input: model, system prompt, messages
  ├─ Record timing: latency_ms
  ├─ Record output: response, tokens used
  ├─ Record status: success, error, throttled
  └─ Calculate metrics: success score, parsed actions

BedrockService#send_message_converse
  ├─ Same recording as above
  └─ Additional: tool definitions, tool calls
```

#### 4. **Training Service** (`app/services/agent_lightning_training_service.rb`)

Orchestrates prompt optimization and RL-based improvements.

```ruby
service = AgentLightningTrainingService.new(entity)

# Check if training is needed
if service.config.should_retrain? && service.config.ready_for_training?
  result = service.execute_training
  # {
  #   success: true,
  #   job_id: "uuid",
  #   traces_used: 250,
  #   improvement: 15.3,
  #   metrics: { success_rate: 85.2, avg_tokens: 1200, ... },
  #   results: { recommendations: [...] }
  # }
end
```

#### 5. **Background Job** (`app/jobs/run_agent_lightning_training_job.rb`)

Scheduled job for periodic training (daily by default).

```ruby
# Add to Clockwork or your scheduler:
RunAgentLightningTrainingJob.perform_later(entity_id)
# or: RunAgentLightningTrainingJob.perform_later  # for all enabled entities
```

## Setup Instructions

### 1. Database Setup

Run migrations to create training tables:

```bash
rails db:migrate
```

This creates:
- `agent_lightning_traces` - Core trace collection
- `agent_llm_calls` - LLM call tracking
- `agent_tool_executions` - Tool execution tracking
- `agent_phase_executions` - Phase execution tracking
- `agent_rewards` - Reward signals
- `agent_training_jobs` - Training job history
- `agent_lightning_configs` - Entity configuration

### 2. Configure Agent Lightning

For each entity, create a default configuration:

```ruby
entity = Entity.find(1)
config = entity.create_agent_lightning_config!(
  enabled: true,
  mode: "observing",  # observing, optimizing, or training
  training_strategy: "prompt_optimization",  # or: supervised_finetuning, rl_training
  retrain_frequency_hours: 24,
  trace_retention_days: 90,
  min_traces_for_training: 100,
  optimization_targets: {
    "reduce_token_usage" => 0.3,
    "improve_success_rate" => 0.5,
    "reduce_latency" => 0.2
  },
  learning_parameters: {
    "learning_rate" => 0.001,
    "batch_size" => 32,
    "num_epochs" => 3
  }
)
```

### 3. Enable Automatic Instrumentation

BedrockService automatically instruments LLM calls when:
1. `entity` and `user` are set on the BedrockService instance
2. Agent Lightning config is enabled for that entity

In ScoutController:

```ruby
def chat_stream
  # ... existing code ...
  bedrock_service = BedrockService.new(
    custom_model_id: nil,
    user: current_user,
    entity: current_entity  # Agent Lightning uses this
  )
  # ... rest of implementation ...
end
```

### 4. Schedule Training Jobs

Add to `config/clock.rb` (if using Clockwork):

```ruby
every(1.day, 'Run Agent Lightning training', at: '02:00') do
  RunAgentLightningTrainingJob.perform_later
end
```

Or add to cron/your scheduler:
```bash
0 2 * * * cd /path/to/app && bin/rails runner 'RunAgentLightningTrainingJob.perform_now'
```

## Usage Examples

### Recording a Workflow Execution

```ruby
class ScoutController < ApplicationController
  def chat_stream
    current_entity = load_current_entity
    current_user = load_current_user

    # Initialize lightning store
    lightning_store = LightningStoreService.new(current_entity, current_user)

    # Start trace
    trace = lightning_store.start_workflow_trace(
      workflow_execution,
      task_session,
      user_message
    )

    # ... execute workflow ...

    # Record outcomes and complete trace
    if workflow_succeeded
      lightning_store.complete_trace(
        output_data: { result: "success", outcome: result_data },
        duration_ms: elapsed_time
      )

      # Record positive reward
      lightning_store.record_reward(
        reward_type: "completion",
        reward_value: 0.9,  # High satisfaction
        source: "automated"
      )
    else
      lightning_store.complete_trace(
        output_data: { result: "failure", error: error_message },
        status: "failed"
      )

      # Record negative reward
      lightning_store.record_reward(
        reward_type: "completion",
        reward_value: 0.1,  # Low satisfaction
        source: "automated"
      )
    end
  end
end
```

### Manual Reward Recording

```ruby
# Record user satisfaction feedback
trace = AgentLightningTrace.find_by(trace_id: "...")
AgentReward.create!(
  entity: current_entity,
  agent_lightning_trace: trace,
  user: current_user,
  reward_type: "user_feedback",
  reward_value: 0.95,  # User rated it 5/5
  source: "user",
  reason: "User explicitly marked as helpful"
)
```

### Running Training Manually

```ruby
service = AgentLightningTrainingService.new(current_entity)
result = service.execute_training

puts "Training result: #{result[:success]}"
puts "Improvement: #{result[:improvement]}%"
puts "Metrics: #{result[:metrics]}"
```

## Configuration Options

### Modes

- **observing**: Only collect traces, no training
- **optimizing**: Collect traces and run periodic training
- **training**: Actively using trained models

### Training Strategies

#### 1. Prompt Optimization
Best for: Quick improvements in instruction clarity

```ruby
training_strategy: "prompt_optimization"
```
Analyzes successful vs. failed traces to recommend prompt improvements.

#### 2. Supervised Fine-Tuning
Best for: Large-scale model improvement

```ruby
training_strategy: "supervised_finetuning"
```
Prepares dataset of successful interactions for potential model fine-tuning.

#### 3. RL Training (Hierarchical RL)
Best for: Complex, multi-step workflows

```ruby
training_strategy: "rl_training"
```
Uses rewards and trajectory data for hierarchical RL training.

## Monitoring and Analytics

### Training Job Status

```ruby
# Get last training job
last_job = AgentTrainingJob.where(entity: current_entity).recent.first

puts "Status: #{last_job.status}"  # pending, running, completed, failed
puts "Traces used: #{last_job.traces_used}"
puts "Improvement: #{last_job.improvement_score}%"
puts "Results: #{last_job.training_results}"
```

### Trace Analytics

```ruby
# Get metrics for recent traces
traces = current_entity.agent_lightning_traces.recent.limit(100)

metrics = {
  total: traces.count,
  avg_duration: traces.average(:duration_ms),
  avg_cost: traces.average(:cost_estimate),
  success_rate: (traces.count { |t| t.reward_signal > 0.7 }.to_f / traces.count * 100),
  avg_tokens: traces.average(:token_count)
}
```

### LLM Call Performance

```ruby
# Analyze LLM call performance by role
llm_calls = current_entity.agent_llm_calls.recent.limit(500)

by_role = llm_calls.group_by(&:agent_role).map do |role, calls|
  {
    role: role,
    count: calls.count,
    avg_tokens: calls.average(:total_tokens),
    success_rate: (calls.count { |c| c.status == "success" }.to_f / calls.count * 100),
    avg_latency: calls.average(:latency_ms)
  }
end
```

## Performance Considerations

### Token Usage
- **Input caching**: Agent Lightning uses Anthropic prompt caching to reduce costs 90% on repeated patterns
- **Cost tracking**: All token usage is tracked for optimization
- **Efficiency metrics**: Monitor cost per trace and optimize tool selection

### Storage
- **Retention policy**: Configurable trace retention (default: 90 days)
- **Cleanup**: Old traces are automatically cleaned up
- **Indexes**: Database indexes optimize trace queries

### Training Frequency
- **Default**: Every 24 hours
- **Min traces**: 100 required for training
- **Customizable**: Set `retrain_frequency_hours` per entity

## Integration with Scout Features

### Workflow Execution
- Traces captured automatically for all workflow types
- Phase-by-phase tracking
- Success criteria evaluation

### Tool Usage
- All tool calls are instrumented
- Success/failure tracking
- Latency measurement

### LLM Interactions
- System prompts recorded for optimization
- Response quality scored
- Action patterns analyzed

## Advanced: Custom Instrumentation

### Add Custom Metrics

```ruby
lightning_store.record_llm_call(
  model: "claude-sonnet-4-5",
  agent_role: "executor",
  system_prompt: system_prompt,
  user_messages: messages,
  response_content: response,
  input_tokens: tokens[:input],
  output_tokens: tokens[:output],
  latency_ms: latency,
  status: "success",
  parsed_actions: JSON.parse(response),  # Your custom parsing
  success_score: calculate_score(response)  # Your custom scoring
)
```

### Custom Reward Calculation

```ruby
def calculate_reward(trace)
  rewards = []

  # Reward token efficiency
  token_efficiency = 1 - (trace.token_count / 4000.0)
  rewards << token_efficiency * 0.3 if token_efficiency > 0.5

  # Reward speed
  speed_score = 1 - (trace.duration_ms / 30000.0)
  rewards << speed_score * 0.2 if speed_score > 0.5

  # Reward success rate
  success_rate = trace.success_rate / 100.0
  rewards << success_rate * 0.5

  rewards.sum
end
```

## Troubleshooting

### Traces not being recorded
1. Check if Agent Lightning is enabled: `entity.agent_lightning_config.enabled?`
2. Verify user and entity are passed to BedrockService
3. Check for errors in `Rails.logger` for "Agent Lightning"

### Training not running
1. Verify cron/scheduler is running training job
2. Check: `config.should_retrain?` returns true
3. Check: `config.ready_for_training?` returns true
4. Check: At least `min_traces_for_training` traces exist with rewards

### High token costs
1. Review `optimization_targets` configuration
2. Check for verbose system prompts
3. Monitor "reduce_token_usage" metric
4. Consider enabling prompt caching

## Future Enhancements

1. **Multi-model support**: Train different models for different agent roles
2. **Real-time feedback**: Incorporate user feedback during execution
3. **A/B testing**: Compare different prompt versions
4. **Model rollback**: Revert to previous prompts if quality degrades
5. **Distributed training**: Support training across multiple GPU/TPU systems
6. **Custom RL algorithms**: Implement domain-specific RL algorithms

## API Reference

### LightningStoreService

```ruby
# Initialization
service = LightningStoreService.new(entity, user)

# Methods
trace = service.start_workflow_trace(workflow_execution, task_session, request_text)
call = service.record_llm_call(...)
execution = service.record_tool_execution(...)
phase = service.record_phase_execution(...)
service.update_phase_execution(phase_exec, attributes)
service.add_step(step_description, status, metadata)
service.complete_trace(output_data, duration_ms, status)
reward = service.record_reward(reward_type, reward_value, source, reason)
service.mark_training_ready
trace = service.current_trace
training_data = service.get_training_data
```

### AgentLightningTrainingService

```ruby
# Initialization
service = AgentLightningTrainingService.new(entity)

# Methods
ready = service.config.should_retrain?
ready = service.config.ready_for_training?
result = service.execute_training
result = service.run_training_if_ready
metrics = service.analyze_training_data(training_data)
```

## Related Documentation

- [Prompt Caching Guide](PROMPT_CACHING_GUIDE.md) - For understanding token optimization
- [Workflow V2 Guide](WORKFLOW_V2_EXECUTIVE_SUMMARY.md) - For workflow execution details
- [Agent Architecture](AGENT_ARCHITECTURE.md) - For overall agent system design
