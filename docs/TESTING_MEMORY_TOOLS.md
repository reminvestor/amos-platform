# Testing Scout Memory Tools

## How Scout's Memory Works

Scout has two layers of memory:

### 1. Active Context Window (Automatic - No Tools)
- **Source**: PostgreSQL (last 20 messages)
- **Access**: Automatic - Scout always sees these
- **When**: Every request
- **Visible to you**: Scout just answers normally, doesn't mention any tools

**Example:**
```
You (message 45): "What's my budget?"
Scout: "Your budget is $50,000" ← Used active context (message 44 mentioned budget)
```

### 2. Extended History (Tool-Based - Redis)
- **Source**: Redis (all messages up to 1000)
- **Access**: Scout must call a memory tool
- **When**: User references something beyond last 20 messages
- **Visible to you**: Scout will mention using tools

**Example:**
```
You (message 51): "What did I say about budget at the beginning?"
Scout: "Let me search our conversation history..."
       🔧 Using tool: search_history (keywords: "budget")
       "You mentioned a budget of $50,000 in message 2."
```

## How to Test and See the Difference

### Test 1: Active Window (No Tools)
1. Send exactly 5 messages
2. Ask about message 1-5
3. **Expected**: Scout answers WITHOUT using tools (it's in active window)

```
Message 1: "My budget is $50,000"
Message 2: "I want email campaigns"
Message 3: "Target tech professionals"
Message 4: "Launch in November"
Message 5: "What was my budget?"

Scout responds: "Your budget is $50,000" (no tools used)
```

### Test 2: Beyond Active Window (Uses Tools)
1. Send 30 messages
2. Ask about message 1-10 (beyond active window)
3. **Expected**: Scout uses `search_history` or `retrieve_history`

```
Messages 1-30: [Long conversation about campaign planning]
Message 31: "What did I say about budget in the beginning?"

Scout responds:
"Let me search our earlier conversation..."
🔧 Using search_history(keywords: "budget")
"You mentioned a budget of $50,000 in message 2."
```

## Visual Indicators

### Scout Using Active Memory (No Tools)
```
You: What's my target audience?
Scout: Based on what you mentioned, your target audience is tech professionals aged 25-40.
```
**No tool mentions** = Used active 20-message window

### Scout Using Extended Memory (Tools)
```
You: What did we discuss at the very beginning?
Scout: Let me retrieve our earlier messages...
       🔧 retrieve_history(start_index: 1, end_index: 10)
       At the beginning, we discussed your Q4 marketing campaign...
```
**Tool mention** = Retrieved from Redis extended history

## Check Scout's Tool Usage in Browser

Look for these indicators in Scout's response:

1. **Tool Call Messages** (if enabled):
   - "Using search_history..."
   - "Retrieving message history..."
   - "Let me check our earlier conversation..."

2. **Streaming Updates** (you'll see):
   - 🔧 Starting search_history...
   - ✅ Completed search_history

## Check Logs

To see exactly what's happening:

```bash
# Watch Scout's tool usage live
docker exec -i $(docker ps -q -f name=web) tail -f log/development.log | grep -E "Executing tool|search_history|retrieve_history|get_message_count"
```

You'll see:
```
Executing tool: search_history
Executing tool: retrieve_history
Executing tool: get_message_count
```

## Exact Test Scenario

### Setup (Create 30 messages)
```ruby
# In Rails console
session_id = SecureRandom.uuid
memory = Scout::MemoryTools.new(session_id)

# Simulate 30-message conversation
15.times do |i|
  memory.store_message('user', "User message #{i+1}")
  memory.store_message('assistant', "Assistant response #{i+1}")
end

# Now messages 1-10 are beyond active window (20 messages)
# Active window contains messages 11-30
```

### Test Questions

**Question 1 (Should NOT use tools):**
```
"What did I say in message 25?"
→ Scout answers without tools (message 25 is in active window)
```

**Question 2 (SHOULD use tools):**
```
"What did I say in message 5?"
→ Scout calls retrieve_history or search_history (message 5 is beyond active window)
```

**Question 3 (SHOULD use tools):**
```
"Search our conversation for the word 'budget'"
→ Scout calls search_history (explicit request)
```

## Redis vs PostgreSQL Check

```ruby
# Check message counts
session_id = "your-session-id"

# PostgreSQL (permanent storage)
db_count = ScoutMessage.for_session(session_id).count

# Redis (temporary storage)
memory = Scout::MemoryTools.new(session_id)
redis_count = memory.get_message_count

puts "PostgreSQL: #{db_count} messages (permanent)"
puts "Redis: #{redis_count} messages (2-hour cache)"
puts "Active window: Last 20 messages sent to Scout"
```

## Expected Behavior

| Scenario | Messages in Convo | User Asks About | Scout Should Use |
|----------|-------------------|-----------------|------------------|
| Short conversation | 15 messages | Message 5 | Active window (no tools) |
| Long conversation | 50 messages | Message 5 | Redis tools (retrieve_history) |
| Long conversation | 50 messages | Message 45 | Active window (no tools) |
| Any conversation | Any | "Search for X" | Redis tools (search_history) |
| Any conversation | Any | "How many messages?" | Redis tools (get_message_count) |

## Debug: See What Scout Sees

```ruby
# What's in Scout's active window?
session_id = "your-session-id"
active_window = ScoutMessage.for_session(session_id).oldest_first.last(20)

puts "Scout's Active Window (#{active_window.count} messages):"
active_window.each_with_index do |msg, i|
  puts "#{i+1}. [#{msg.role}]: #{msg.content[0..50]}..."
end

# What's in Redis?
memory = Scout::MemoryTools.new(session_id)
all_messages = memory.get_full_history

puts "\nRedis Extended History (#{all_messages.count} messages):"
all_messages.each do |msg|
  puts "#{msg[:index]}. [#{msg[:role]}]: #{msg[:content][0..50]}..."
end
```

## Quick Test Script

Run this to see the difference:

```bash
docker exec -i $(docker ps -q -f name=web) bin/rails runner "
session_id = SecureRandom.uuid
memory = Scout::MemoryTools.new(session_id)

# Create 30 messages
30.times { |i| memory.store_message('user', \"Message #{i+1}: Test\", {}) }

puts 'Created 30 messages'
puts \"Active window: Last 20 (messages 11-30)\"
puts \"Beyond active window: First 10 (messages 1-10)\"
puts
puts 'If you ask about messages 11-30: Scout uses active memory (no tools)'
puts 'If you ask about messages 1-10: Scout uses Redis tools'
"
```

## Summary

**You'll know Scout is using Redis memory tools when:**
- ✅ Scout mentions using a tool (search_history, retrieve_history, get_message_count)
- ✅ You see tool execution in streaming updates (🔧 Starting...)
- ✅ Logs show "Executing tool: search_history"
- ✅ Scout says things like "Let me search our earlier conversation..."

**Scout is using active memory (PostgreSQL) when:**
- ✅ Scout just answers normally without mentioning tools
- ✅ No tool execution messages appear
- ✅ Logs show no tool calls
- ✅ Question is about recent messages (last 20)
