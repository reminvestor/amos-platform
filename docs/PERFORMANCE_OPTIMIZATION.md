# Performance Optimization Guide

## Current Bottlenecks (February 2026)

### 1. LLM Round-Trip Loop (BIGGEST IMPACT)

**Problem:** Each tool call requires a full LLM continuation call.

```
User Message → LLM (2s) → Tool 1 (0.5s) → LLM (2s) → Tool 2 (0.5s) → LLM (2s) → Response
Total: 7+ seconds for 2 tools
```

**Current Settings:**
- `max_tool_turns = 15` in `bedrock_service.rb:1116`
- No parallel tool execution

**Optimization Options:**
1. **Batch tool calls** - Execute multiple tools in parallel when possible
2. **Reduce max turns** - Lower `max_tool_turns` from 15 to 10 for simpler flows
3. **Pre-wire common patterns** - For Stripe charges, skip tool discovery

### 2. UnifiedPreprocessorService (1000ms timeout)

**Problem:** Runs 5 parallel threads, each with 1000ms timeout.

**Location:** `app/services/unified_preprocessor_service.rb:36`

```ruby
THREAD_TIMEOUT_MS = 1000  # Currently 1 second
```

**What it does:**
1. Canvas routing
2. Tool discovery (RAG search - 600-1000ms)
3. Agent pre-warming
4. Integration context loading
5. Module context loading

**Optimization Options:**
1. **Reduce timeout** - Lower to 500ms for snappier response
2. **Fast path more aggressively** - Skip preprocessing for common patterns
3. **Cache tool discovery** - RAG results are deterministic for same prompts

### 3. RAG Vector Search (600-1000ms)

**Problem:** `TieredDiscoveryService.discover_tools` uses vector similarity search.

**Location:** `app/services/tiered_discovery_service.rb`

**Optimization Options:**
1. **Cache embeddings** - Hash(message) → tools mapping
2. **Pre-compute common queries** - "Stripe", "customers", "charges" etc.
3. **Reduce search scope** - Only search category-relevant tools

### 4. Error Recovery Loops

**Problem:** Failed tool calls trigger retry logic → more LLM calls.

**Example from Stripe issue:**
```
execute_integration_action(operation: "list_charges", params: {order: "desc"})
→ 400 Bad Request
→ LLM continuation to diagnose
→ discover_tools to find alternatives
→ More LLM calls...
```

**Optimization Options:**
1. **Parameter validation** - Validate params BEFORE calling API
2. **Better error messages** - Tell LLM exactly what's wrong
3. **Circuit breaker** - After 2 failures, give up gracefully

## Quick Fixes

### 1. Reduce Preprocessor Timeout (Low Risk)

```ruby
# app/services/unified_preprocessor_service.rb
THREAD_TIMEOUT_MS = 500  # Was 1000
```

### 2. Add Parameter Validation to Integration Tools (Medium Risk)

```ruby
# app/services/tools/execute_integration_action_tool.rb
def validate_params_before_call(operation, params)
  schema = operation.request_schema
  invalid = params.keys - schema['properties'].keys
  if invalid.any?
    return { error: "Invalid params: #{invalid.join(', ')}" }
  end
  nil
end
```

### 3. Cache Tool Discovery Results (Medium Risk)

```ruby
# app/services/tiered_discovery_service.rb
def discover_tools_cached(prompt:)
  cache_key = "tool_discovery:#{Digest::SHA256.hexdigest(prompt)[0..16]}"
  Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
    discover_tools(prompt: prompt)
  end
end
```

### 4. Parallel Tool Execution (Higher Risk)

When LLM requests multiple tools, execute them in parallel:

```ruby
# app/services/scout_generic_tools_service_v2.rb
def execute_tool_calls_parallel(tool_calls, progress_callback)
  threads = tool_calls.map do |tc|
    Thread.new { execute_single_tool(tc, progress_callback) }
  end
  threads.map(&:value)
end
```

## Monitoring Latency

Add to your logs:

```ruby
# Track per-request timing
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
# ... do work ...
elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
Rails.logger.info "[PERF] #{operation_name}: #{elapsed}ms"
```

Key metrics to track:
- Preprocessor latency
- First LLM call latency
- Tool execution latency
- Total tool loop iterations
- Total request time

## AWS Bedrock Specific

Qwen 3 32B via OpenRouter through Bedrock:
- Cold start: ~3s
- Warm: ~1-2s per call
- Token streaming: ~50-100 tokens/sec

For faster responses:
1. Use Claude Haiku for simple tasks (~500ms)
2. Use Qwen3-Next-80B for tool tasks (best tool success rate)
3. Avoid DeepSeek R1 for tool-heavy workflows (tool success rate issues)
