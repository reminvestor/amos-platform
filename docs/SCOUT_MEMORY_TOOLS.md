# Scout Memory Tools - Extended Conversation History

## Overview

Scout now supports extended conversation history through Redis storage. This enables Scout to handle 100+ message conversations while keeping token usage low by maintaining only the most recent 20 messages in the active context window.

## Architecture

### Three-Layer Storage

1. **Active Context Window (20 messages)** - Passed to Bedrock AI
   - Last 20 messages from PostgreSQL
   - Keeps token usage manageable (~10-15K tokens)
   - Loaded for every request via `persisted_history_last_k(20)`

2. **Redis Extended History (up to 1000 messages)** - On-demand retrieval
   - All messages stored incrementally as conversation progresses
   - 2-hour TTL (configurable via `Scout::MemoryTools::SESSION_TTL`)
   - Accessible via memory tools when Scout needs older context

3. **PostgreSQL Persistent Storage** - Permanent record
   - All messages permanently stored in `scout_messages` table
   - Used for analytics, exports, and session management
   - Can sync to Redis if needed

### Message Flow

```
User sends message
    ↓
Controller saves to PostgreSQL (ScoutMessage.create!)
    ↓
Controller saves to Redis (Scout::MemoryTools.store_message)
    ↓
Load last 20 messages from PostgreSQL for active window
    ↓
Send to Bedrock with active window + memory retrieval tools
    ↓
Scout can call memory tools to retrieve older messages as needed
```

## Memory Tools

Scout has three tools available for retrieving extended history:

### 1. `retrieve_history`
Get older messages by range or count.

**When Scout uses it:**
- User says "What did we discuss at the beginning?"
- User references something not in recent 20 messages
- Scout needs more context for analysis

**Parameters:**
- `start_index` (integer): Starting message index (1-based)
- `end_index` (integer): Ending message index (1-based, inclusive)
- `count` (integer): Number of recent messages to retrieve (default: 20)

**Example calls:**
```ruby
# Get messages 1-30 (early conversation)
retrieve_history(start_index: 1, end_index: 30)

# Get last 50 messages
retrieve_history(count: 50)
```

### 2. `get_message_count`
Get total message count to understand conversation length.

**When Scout uses it:**
- User asks "How long have we been talking?"
- Scout wants to know if there's more history beyond active window
- Deciding whether to fetch older messages

**Returns:**
```json
{
  "total_messages": 85,
  "active_window_size": 20,
  "messages_beyond_window": 65,
  "session_stats": {
    "session_id": "abc123...",
    "redis_available": true,
    "ttl_remaining": 6842
  }
}
```

### 3. `search_history`
Search for messages containing specific keywords.

**When Scout uses it:**
- User says "What did I say about the budget?"
- User references specific topic from earlier
- Scout needs to find relevant past context

**Parameters:**
- `keywords` (string, required): Keywords to search for
- `role` (string, optional): Filter by "user" or "assistant"
- `max_results` (integer): Maximum results to return (default: 10)

**Example calls:**
```ruby
# Find budget discussions
search_history(keywords: "budget", max_results: 5)

# Find user's earlier questions about campaigns
search_history(keywords: "campaign", role: "user")
```

## Implementation Details

### Redis Keys Structure

```
scout:{session_id}:messages         # Redis LIST of message JSON objects
scout:{session_id}:message_count    # Integer counter
```

### Message Format in Redis

```json
{
  "index": 42,
  "role": "user",
  "content": "What's my campaign budget?",
  "timestamp": "2025-10-14T20:30:00Z",
  "metadata": {}
}
```

### Configuration

Located in `lib/scout/memory_tools.rb`:

```ruby
ACTIVE_WINDOW_SIZE = 20      # Messages kept in active context
MAX_HISTORY_SIZE = 1000      # Maximum messages stored in Redis
SESSION_TTL = 7200           # 2 hours (seconds)
```

## Usage Examples

### Example 1: Long Conversation

```
User: [Message 1-50 about project requirements]
User (Message 51): "What did I say about the budget at the beginning?"

Scout thinks:
- My active window has messages 31-50
- User is referencing "budget" from earlier
- I should search for budget discussions

Scout calls: search_history(keywords: "budget", role: "user", max_results: 3)

Result: Finds messages 8, 12, and 15 mentioning budget
Scout responds: "Earlier you mentioned a budget of $50k in message 8..."
```

### Example 2: Context Retrieval

```
User: [Messages 1-70 discussing landing page design]
User (Message 71): "Can you review what we decided in the first conversation?"

Scout thinks:
- My active window starts at message 51
- User wants early conversation summary
- I should retrieve the beginning

Scout calls: retrieve_history(start_index: 1, end_index: 20)

Result: Gets messages 1-20 from Redis
Scout responds: "In our initial conversation, we decided on..."
```

### Example 3: Smart Context Loading

```
User: [Messages 1-100]
User (Message 101): "How many messages have we exchanged?"

Scout calls: get_message_count()

Result: { "total_messages": 101, "messages_beyond_window": 81 }
Scout responds: "We've exchanged 101 messages so far..."
```

## Admin Tools

### Session Management API

**View all sessions:**
```
GET /admin/scout_sessions
```

**View specific session:**
```
GET /admin/scout_sessions/:session_id
```

**Delete session (clears DB + Redis + Cache):**
```
DELETE /admin/scout_sessions/:session_id
```

**Sync database messages to Redis:**
```
POST /admin/scout_sessions/:session_id/sync_redis
```

### Controller Helper Methods

```ruby
# In ScoutController
def save_scout_message(role, message, metadata: {})
  # Saves to PostgreSQL
  ScoutMessage.create!(...)

  # Saves to Redis
  memory = Scout::MemoryTools.new(session_id)
  memory.store_message(role, message, metadata)
end

def clear_conversation
  # Clears all three storage layers
  Rails.cache.delete(...)
  memory.clear_session
  session.delete(:scout_session_id)
end
```

### Manual Redis Management

```ruby
# In Rails console
session_id = "your-session-id-here"
memory = Scout::MemoryTools.new(session_id)

# Get stats
memory.session_stats
# => {
#   session_id: "...",
#   total_messages: 85,
#   redis_available: true,
#   ttl_remaining: 6842
# }

# Get full history
memory.get_full_history

# Search
memory.search_history(keywords: "budget", max_results: 10)

# Clear
memory.clear_session

# Sync from database
ScoutMessage.for_session(session_id).oldest_first.each do |msg|
  memory.store_message(msg.role, msg.content, msg.metadata || {})
end
```

## Error Handling

Memory tools gracefully degrade if Redis is unavailable:

1. **Storage fails** - Message still saved to PostgreSQL
2. **Retrieval fails** - Scout receives error response from tool
3. **Redis unavailable** - Application continues working, just without extended history

All Redis operations are wrapped in error handlers that log warnings but don't break the application.

## Performance Considerations

### Token Usage

- **Without memory tools**: Send last 20 messages (~10-15K tokens)
- **With memory tools**: Scout only loads older messages when needed
- **100-message conversation**: Active window = 20 messages, 80 messages available via tools

### Redis Performance

- **Write**: O(1) per message (RPUSH operation)
- **Read range**: O(N) where N = number of messages retrieved
- **Search**: O(N) where N = total messages (searches in Ruby, not Redis)
- **Memory**: ~1KB per message * 1000 max = ~1MB per session

### When to Sync Redis

Sync database → Redis when:
- Testing memory tools with existing conversations
- Redis was temporarily down and missed messages
- Recovering from Redis data loss

Don't sync:
- During normal operation (automatic incremental storage)
- For every request (inefficient)

## System Prompt Integration

Scout is informed about memory tools in its system prompt:

```
CONVERSATION HISTORY:
You have access to the last 20 messages in your active context window. If the user references
something from earlier in the conversation that you don't see in your current context, you can:
- Use get_message_count to see how many total messages exist
- Use retrieve_history to get older messages by index range or count
- Use search_history to find messages containing specific keywords

Example: If user says "What did I say about the budget earlier?" and you don't see budget
discussions in your recent messages, use search_history(keywords: "budget") to find them.
```

## Testing Memory Tools

### Manual Test Flow

1. **Start a conversation** (generates session_id)
2. **Send 30+ messages** to exceed active window
3. **Reference something from early messages**
4. **Watch Scout use memory tools** in logs

```ruby
# Check Redis storage
session_id = "your-session-id"
memory = Scout::MemoryTools.new(session_id)
puts memory.session_stats
puts memory.get_full_history.count
```

### Test Queries

```
User: "What did I say about budget in the first few messages?"
Expected: Scout calls search_history(keywords: "budget")

User: "How many messages have we sent?"
Expected: Scout calls get_message_count()

User: "Summarize our initial conversation"
Expected: Scout calls retrieve_history(start_index: 1, end_index: 10)
```

## Troubleshooting

### Redis Connection Issues

Check Redis status:
```bash
podman compose ps redis
podman compose logs redis
```

Test connection in Rails console:
```ruby
$redis.ping  # Should return "PONG"
```

### Messages Not Storing

Check logs for warnings:
```bash
grep "Failed to store message in Redis" log/development.log
```

Verify storage manually:
```ruby
session_id = "..."
memory = Scout::MemoryTools.new(session_id)
memory.redis_available?  # Should be true
memory.store_message("user", "test", {})
memory.get_message_count  # Should increment
```

### Scout Not Using Tools

1. **Check active window size** - Messages might still be in recent 20
2. **Check tool availability** - Memory tools should be in tool catalog
3. **Check query phrasing** - Try explicit requests like "search earlier messages for X"
4. **Check logs** - Scout logs tool decisions

### Session Expired

Redis sessions expire after 2 hours (TTL). Messages are still in PostgreSQL:

```ruby
# Restore from database
session_id = "..."
memory = Scout::MemoryTools.new(session_id)

ScoutMessage.for_session(session_id).oldest_first.each do |msg|
  memory.store_message(msg.role, msg.content, msg.metadata || {})
end
```

## Future Enhancements

Potential improvements:

1. **Semantic Search** - Use embeddings for better context retrieval
2. **Auto-Summarization** - Compress old messages into summaries
3. **Conversation Branches** - Support multiple conversation threads
4. **User Preferences** - Configurable window sizes per user
5. **Message Prioritization** - Keep important messages in active window longer
6. **Redis Cluster** - Scale to millions of concurrent sessions

## Related Files

- `lib/scout/memory_tools.rb` - Core memory management
- `app/services/tools/retrieve_history_tool.rb` - History retrieval tool
- `app/services/tools/get_message_count_tool.rb` - Message count tool
- `app/services/tools/search_history_tool.rb` - History search tool
- `app/controllers/scout_controller.rb` - Message saving and loading
- `app/controllers/admin/scout_sessions_controller.rb` - Admin session management
- `app/services/scout_generic_tools_service_v2.rb` - Tool integration
- `config/initializers/redis.rb` - Redis configuration
