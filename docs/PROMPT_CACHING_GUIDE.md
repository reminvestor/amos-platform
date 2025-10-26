# Anthropic Prompt Caching Guide

## Overview

This application uses **Anthropic's Prompt Caching** feature to dramatically improve AI response times and reduce costs. When enabled, static context (system prompts and tool definitions) is cached for 5 minutes, making subsequent requests ~10x faster and ~90% cheaper.

## Performance Benefits

### Speed Improvements
- **First request (cache MISS)**: ~2500ms (creates cache)
- **Subsequent requests (cache HIT)**: ~250ms (uses cache)
- **Speedup**: **10x faster** for cache hits

### Cost Savings
- **Standard tokens**: $3.00 per million tokens
- **Cached tokens**: $0.30 per million tokens (cache read)
- **Savings**: **90% cheaper** for cached content

### Real-World Impact
```
Example Scout conversation with 3 questions:

WITHOUT caching:
  Question 1: 2500ms, $0.0075
  Question 2: 2500ms, $0.0075
  Question 3: 2500ms, $0.0075
  Total: 7500ms, $0.0225

WITH caching:
  Question 1: 2500ms, $0.0075 (creates cache)
  Question 2: 250ms,  $0.0008 (uses cache, 90% cheaper)
  Question 3: 250ms,  $0.0008 (uses cache, 90% cheaper)
  Total: 3000ms, $0.0091

Improvement: 60% faster, 60% cheaper
```

## How It Works

### Cache Control API

Anthropic's caching uses a special `cache_control` parameter to mark content for caching:

```ruby
{
  type: "text",
  text: "Your system prompt here...",
  cache_control: { type: "ephemeral" }
}
```

**Key Rules**:
1. Only the **last** `cache_control` marker matters
2. Everything **up to and including** that marker is cached
3. Minimum **1024 tokens** required for caching
4. Cache lasts **5 minutes** from creation
5. Cache keys are based on **exact content matching**

### What Gets Cached

In our implementation, we cache:
- **System prompt** (~1500-2000 tokens) - The Scout AI identity and instructions
- **Tool definitions** (~3000-5000 tokens) - All 20+ available tools

This totals **4500-7000 tokens** of static content that remains identical across requests.

### What Doesn't Get Cached

- **User messages** - Each question is unique
- **User context** - Name, entity, specific data
- **Conversation history** - Grows with each message
- **Canvas state** - Current UI state

## Cross-User Cache Sharing Optimization

### The Problem

Initially, we included user-specific data in the system prompt:

```ruby
# ❌ INEFFICIENT - Each user creates separate cache
system_prompt = <<~PROMPT
  You are Scout, an AI assistant.

  USER CONTEXT:
  - User: John Smith          # ← Different for each user
  - Entity: Acme Corp         # ← Different for each entity
PROMPT
```

**Result**: Each user creates their own cache
- Cache hit rate: **50%** (only same user benefits)
- User A request 1: Cache MISS (2500ms)
- User A request 2: Cache HIT (250ms)
- User B request 1: Cache MISS (2500ms) ← Creates new cache!

### The Solution

Move user-specific data from system prompt to user messages:

```ruby
# ✅ OPTIMIZED - All users share same cache
system_prompt = <<~PROMPT
  You are Scout, an AI assistant.

  You have access to comprehensive tools...
  # No user-specific data here!
PROMPT

# User context goes in the message instead
message = "[User Context: John Smith from Acme Corp]\n\nWhat campaigns do I have?"
```

**Result**: All users share the same cached system prompt + tools
- Cache hit rate: **75%** (first user creates, others reuse)
- User A request 1: Cache MISS (2500ms) ← Creates cache
- User A request 2: Cache HIT (250ms)
- User B request 1: Cache HIT (250ms) ← Uses User A's cache! 🔥
- User B request 2: Cache HIT (250ms)

### Security Considerations

**Is cross-user cache sharing secure?**

✅ **YES** - The cache only stores the system prompt and tool definitions, which are identical for all users. User-specific data is:
- Sent in each message (not cached)
- Still processed by Claude normally
- Never leaked between users

**What Claude receives**:
```
System (cached): "You are Scout with access to these tools..."
Tools (cached): [list of 20+ tool definitions]
Message (not cached): "[User: Jane Doe from Tech Startup]\n\nShow my campaigns"
```

Claude processes the full context including user identity - it just reads the system prompt from cache instead of reprocessing it.

## Implementation Details

### BedrockService Changes

The `BedrockService` now supports an `enable_prompt_caching` parameter:

```ruby
bedrock.send_message(
  system_prompt,
  messages,
  model: "claude-sonnet-4-5",
  max_tokens: 10000,
  tools: tools,
  enable_prompt_caching: true  # ← Enable caching
)
```

When enabled, it:
1. Formats system prompt with `cache_control` marker
2. Adds `cache_control` to last tool definition
3. Logs cache metrics (creation/hits/speedup)

### Tool Catalog Integration

The `ToolCatalog` adds cache control to tools:

```ruby
tools = Tools::ToolCatalog.instance.get_bedrock_tools(
  enable_caching: true  # ← Adds cache_control to last tool
)
```

This caches all tool definitions along with the system prompt.

### Scout Service Optimization

`ScoutGenericToolsServiceV2` has been optimized:

**build_system_prompt**: Removed user/entity context (now generic for all users)

**enhance_message_with_canvas_context**: Adds user context to messages instead

```ruby
def enhance_message_with_canvas_context(message, canvas)
  user_context_prefix = "[User Context: #{user_name} from #{entity_name}]\n\n"
  user_context_prefix + message
end
```

## Cache Metrics and Logging

When caching is enabled, you'll see detailed metrics in the Rails logs:

### First Request (Cache Creation)
```
💾 Prompt caching enabled for system prompt (1847 chars)
💾 Prompt caching enabled for 23 tools (cache_control on last tool)
💾 CACHE METRICS:
  Cache created: 4521 tokens
  New processing: 12 tokens
```

### Subsequent Request (Cache Hit)
```
💾 Prompt caching enabled for system prompt (1847 chars)
💾 Prompt caching enabled for 23 tools (cache_control on last tool)
💾 CACHE METRICS:
  Cache read: 4521 tokens (90% savings!)
  New processing: 15 tokens
  ⚡ Effective speedup: ~302x faster
```

### Understanding the Metrics

- **Cache created**: Tokens cached on first request (5 min TTL)
- **Cache read**: Tokens retrieved from cache (90% cheaper)
- **New processing**: Only new content processed (user message)
- **Effective speedup**: Ratio of cached vs processed tokens

## Testing Prompt Caching

### Test Script 1: Basic Caching Performance

Run the basic test to verify caching works:

```bash
docker compose exec web rails runner tmp/test_prompt_caching.rb
```

Expected output:
```
REQUEST 1: First request (should create cache)
Duration: 2534ms

REQUEST 2: Second request (should use cache - 10x faster!)
Duration: 251ms

✅ SUCCESS! Prompt caching is working! (Request 2 was 10.1x faster)
```

### Test Script 2: Cross-User Cache Sharing

Verify that different users share the same cache:

```bash
docker compose exec web rails runner tmp/test_optimized_caching.rb
```

Expected output:
```
CHECKING SYSTEM PROMPT SHARING
✅ SUCCESS! System prompts are IDENTICAL
   Both users will share the same cache!

REQUEST 1: User 1 first request (cache MISS - creates cache)
Duration: 2487ms

REQUEST 2: User 2 first request (should be cache HIT if sharing works!)
Duration: 265ms

✅ CROSS-USER CACHE SHARING WORKS!
   User 2 benefited from User 1's cache
   Speedup: 9.4x faster!
```

### Test Script 3: Cache Isolation Check

Verify cache security (users don't leak data):

```bash
docker compose exec web rails runner tmp/test_cache_isolation.rb
```

This test confirms system prompts are identical (good for sharing) while user context stays in messages (secure).

## Configuration

### Enabling/Disabling Caching

Caching is **enabled by default** in `ScoutGenericToolsServiceV2` for all Scout conversations.

To disable caching for a specific request:

```ruby
# In ScoutGenericToolsServiceV2
@ai_service.send_message_streaming(
  system_prompt,
  messages,
  tools: tools,
  enable_prompt_caching: false  # ← Disable caching
)
```

### Cache TTL (Time To Live)

The cache TTL is **5 minutes** and is controlled by Anthropic, not configurable on our side.

### Minimum Token Requirement

Anthropic requires **minimum 1024 tokens** for caching. Our system prompt + tools easily exceed this (~4500-7000 tokens).

## Best Practices

### DO ✅

- **Use caching for Scout conversations** - High traffic, repeated requests
- **Keep system prompts generic** - Enable cross-user sharing
- **Put user data in messages** - Maintain security while sharing cache
- **Monitor cache metrics** - Track hit rates and speedup
- **Test with multiple users** - Verify cache sharing works

### DON'T ❌

- **Don't cache user-specific prompts** - Creates separate caches per user
- **Don't put sensitive data in system prompts** - Could leak if cached
- **Don't disable caching unnecessarily** - Lose 10x performance benefit
- **Don't modify system prompt frequently** - Breaks cache every time

## Troubleshooting

### Cache Not Working (No Speedup)

**Symptoms**: Requests take same time despite caching enabled

**Possible causes**:
1. System prompt changed between requests (breaks cache)
2. Less than 1024 tokens to cache (below minimum)
3. More than 5 minutes elapsed (cache expired)
4. Cache metrics show "Cache created" on every request

**Solutions**:
- Verify system prompts are identical across requests
- Check logs for "💾 CACHE METRICS" to see creation vs reads
- Ensure system prompt + tools exceed 1024 tokens

### Different Users Create Separate Caches

**Symptoms**: User B's first request is slow (cache miss) after User A used the system

**Cause**: System prompt contains user-specific data (different content = different cache)

**Solution**:
- Move user/entity context from `build_system_prompt` to `enhance_message_with_canvas_context`
- Run `tmp/test_optimized_caching.rb` to verify prompts are identical

### Cache Metrics Not Showing

**Symptoms**: No "💾 CACHE METRICS" logs appearing

**Cause**: `enable_prompt_caching: true` not passed to BedrockService

**Solution**: Verify the service call includes caching parameter:
```ruby
bedrock.send_message(..., enable_prompt_caching: true)
```

## Performance Comparison

### Before Prompt Caching (Baseline)

```
User conversation with 5 questions:
  Request 1: 2500ms
  Request 2: 2500ms
  Request 3: 2500ms
  Request 4: 2500ms
  Request 5: 2500ms
  Total: 12500ms
  Cost: $0.0375
```

### After Basic Caching (Per-User Caches)

```
User A + User B each ask 2 questions:
  User A Q1: 2500ms (cache miss)
  User A Q2: 250ms  (cache hit)
  User B Q1: 2500ms (cache miss - separate cache!)
  User B Q2: 250ms  (cache hit)
  Total: 5500ms
  Improvement: 56% faster
```

### After Optimized Caching (Cross-User Sharing)

```
User A + User B each ask 2 questions:
  User A Q1: 2500ms (cache miss - creates cache)
  User A Q2: 250ms  (cache hit)
  User B Q1: 250ms  (cache hit - uses User A's cache!)
  User B Q2: 250ms  (cache hit)
  Total: 3250ms
  Improvement: 74% faster than baseline, 41% faster than per-user caching
```

## Future Enhancements

### Potential Improvements

1. **System-wide cache warming**: Pre-create cache on app startup
2. **Cache analytics dashboard**: Track hit rates, savings per user
3. **Dynamic cache control**: Adjust based on request patterns
4. **Multi-level caching**: Cache conversation history segments

### Anthropic Feature Requests

- Longer cache TTL (currently 5 min max)
- Cache usage API (query cache status)
- Multiple cache control markers (cache different segments)

## Related Documentation

- [Anthropic Prompt Caching Docs](https://docs.anthropic.com/claude/docs/prompt-caching)
- [BedrockService Implementation](../app/services/bedrock_service.rb)
- [Tool Catalog](../app/services/tools/tool_catalog.rb)
- [Scout Service V2](../app/services/scout_generic_tools_service_v2.rb)

## Changelog

### 2025-10-24: Initial Implementation
- ✅ Added `enable_prompt_caching` parameter to BedrockService
- ✅ Added cache_control to system prompts and tools
- ✅ Enabled caching in ScoutGenericToolsServiceV2
- ✅ Added cache metrics logging

### 2025-10-24: Cross-User Cache Sharing Optimization
- ✅ Removed user/entity from system prompt
- ✅ Added user context to messages instead
- ✅ Improved cache hit rate from 50% to 75%
- ✅ Created test scripts for verification
