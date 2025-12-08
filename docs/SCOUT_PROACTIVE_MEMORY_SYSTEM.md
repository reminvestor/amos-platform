# Scout Proactive Memory System

## Overview

Scout's proactive memory system is a sophisticated background processing pipeline that:
1. **Pre-warms relevant memories** before Scout needs them
2. **Extracts insights and patterns** from conversations automatically
3. **Learns and adapts** Scout's behavior based on user interactions
4. **Broadcasts real-time memory hints** during conversations

This creates a more intelligent, contextually-aware assistant that remembers across sessions and anticipates user needs.

## Architecture

### Memory Layers (L1-L4)

```
┌─────────────────────────────────────────────────────────────────┐
│                     UNIFIED MEMORY SYSTEM                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  L1: ACTIVE CONTEXT (15 messages)                              │
│  ├── Rails cache for instant retrieval                         │
│  ├── Always loaded in every prompt                             │
│  └── Auto-invalidates on new message                           │
│                                                                 │
│  L2: RECENT MEMORY (100 messages)                              │
│  ├── Redis + PostgreSQL fallback                               │
│  ├── Quick keyword search                                      │
│  └── 7-day TTL in Redis                                        │
│                                                                 │
│  L3: WORKING MEMORY (Summaries)                                │
│  ├── Daily/Weekly/Topic segments                               │
│  ├── AI-generated summaries with key topics                    │
│  └── Permanent PostgreSQL storage                              │
│                                                                 │
│  L4: LONG-TERM MEMORY (RAG)                                    │
│  ├── Semantic search via RAG store                             │
│  ├── Full conversation history indexed                         │
│  └── Cross-session context retrieval                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Background Jobs

```
┌─────────────────────────────────────────────────────────────────┐
│                    BACKGROUND PROCESSING                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  REAL-TIME JOBS (triggered per-message):                       │
│  ├── ProactiveMemoryJob                                         │
│  │   ├── Analyzes conversation trajectory                      │
│  │   ├── Pre-fetches relevant L3/L4 memories                   │
│  │   ├── Caches results for instant retrieval                  │
│  │   └── Broadcasts memory hints via ActionCable               │
│  │                                                              │
│  └── (triggered every 10 messages)                             │
│      └── ExtractConversationInsightsJob                        │
│          ├── Extracts business insights                        │
│          ├── Learns user preferences/facts/goals               │
│          └── Records Scout learning patterns                   │
│                                                                 │
│  SCHEDULED JOBS (cron):                                        │
│  ├── NightlyLearningJob (2 AM daily)                           │
│  │   ├── Deep pattern analysis across all users                │
│  │   ├── Consolidates similar learnings                        │
│  │   ├── Updates Scout personality per entity                  │
│  │   └── Creates daily/weekly memory segments                  │
│  │                                                              │
│  ├── MemoryCleanupJob (3 AM daily)                             │
│  │   ├── Applies relevance decay to old segments               │
│  │   ├── Archives old messages (after summarization)           │
│  │   └── Cleans orphaned Redis keys                            │
│  │                                                              │
│  └── SummarizeConversationJob (threshold: 30 msgs)             │
│      └── Creates rolling summaries for long conversations       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## ProactiveMemoryJob

The crown jewel of the memory system - runs in parallel during conversations to pre-warm relevant memories.

### How It Works

1. **Triggered**: When user sends a message
2. **Analyzes**: Current message for intent, topics, time references
3. **Fetches**: Relevant memories from L3/L4 in parallel
4. **Caches**: Results for 10 minutes in Rails cache
5. **Broadcasts**: Memory hints via ActionCable

### Context Profile Detection

```ruby
# Detects:
- topics: [:marketing, :email, :landing_page, :integrations, etc.]
- time_references: [:yesterday, :last_week, :past]
- entities_mentioned: [[:agent, 'landing_page'], [:tool, 'search']]
- intent: :question | :command | :continuation | :clarification
- needs_history: true/false (based on time references)
- needs_facts: true/false (based on fact-seeking patterns)
- needs_decisions: true/false (based on decision patterns)
```

### Memory Hint Broadcasts

When relevant memories are found, the job broadcasts a hint:

```javascript
{
  type: 'memory_hint',
  context_summary: "Found 2 conversation segments about marketing",
  segment_count: 2,
  memory_count: 3,
  has_bookmarks: true,
  topics: ['marketing', 'email'],
  timestamp: "2024-12-08T02:00:00Z"
}
```

The UI shows a subtle indicator in the bottom-right corner.

## NightlyLearningJob

Deep analysis job that runs at 2 AM to consolidate learnings across all conversations.

### What It Does

1. **User Pattern Analysis**
   - Timing patterns (when user is most active)
   - Topic patterns (what they frequently discuss)
   - Communication style (brief vs detailed, questions vs commands)

2. **Learning Extraction**
   - Tool usage patterns (what works, what doesn't)
   - Delegation outcomes (which agents succeed for which tasks)
   - Error patterns (common issues to watch for)

3. **Entity-Level Optimization**
   - Peak usage day detection
   - Common workflow sequences

4. **Personality Updates**
   - Adjusts Scout's verbosity based on user preferences
   - Adjusts proactivity based on interaction patterns

### Learning Storage

```ruby
# UserMemory (per user)
- type: 'preference' | 'fact' | 'decision' | 'goal' | 'pattern'
- content: "User prefers brief responses"
- confidence: 0.8
- source: 'observation'

# ScoutLearning (per entity)
- type: 'task_pattern' | 'tool_usage' | 'delegation' | 'error_recovery'
- learning: "delegate_to_agent works well for landing pages"
- success_rate: 0.85
- context: 'landing_page'
```

## Integration Points

### Scout Controller

```ruby
# On every user message:
def save_scout_message(...)
  # ... save message ...
  
  # Trigger proactive memory fetch for next response
  if role == 'user' && message.present?
    trigger_proactive_memory_fetch(session_id, message)
  end
  
  # Trigger insight extraction every 10 messages
  trigger_insight_extraction_if_needed(session_id)
end
```

### UnifiedMemory Context Building

```ruby
def build_context(current_message)
  # First check for pre-warmed proactive memories (instant!)
  proactive = fetch_proactive_memories
  if proactive.present?
    context[:proactive_context] = proactive
    context[:l3] = proactive[:segments]
  end
  
  # Only fetch from DB if proactive cache is empty
  if context[:l3].blank? && needs_history
    context[:l3] = fetch_relevant_segments(current_message)
  end
end
```

### System Prompt Injection

```ruby
def format_for_prompt(context)
  parts = []
  
  # Add proactive context summary
  if context[:proactive_context].present?
    parts << "🧠 PROACTIVE MEMORY: #{context[:proactive_context][:context_summary]}"
  end
  
  # Add memory segments
  if context[:l3].present?
    parts << format_memory_segments(context[:l3])
  end
  
  parts.join("\n\n")
end
```

## ActionCable Integration

### Server Side

```ruby
# scout_channel.rb
def subscribed
  stream_from "scout_channel_#{params[:session_id]}"
  stream_from "scout_user_#{current_user.id}"  # For memory hints
end
```

### Client Side

```javascript
// scout_channel.js
case 'memory_hint':
  // Store for Scout to reference
  window.proactiveMemoryHints.push(data)
  
  // Show subtle indicator
  showMemoryHintIndicator(data)
  break
```

## Database Models

### MemorySegment (L3 Storage)

```ruby
create_table :memory_segments do |t|
  t.references :user
  t.references :entity
  t.string :segment_type  # 'daily', 'weekly', 'topic'
  t.datetime :period_start
  t.datetime :period_end
  t.integer :message_count
  t.text :summary
  t.jsonb :key_topics
  t.jsonb :key_decisions
  t.jsonb :action_items
  t.text :context_snapshot
  t.boolean :active, default: true
  t.float :relevance_decay, default: 1.0
end
```

### UserMemory (Learned Facts)

```ruby
create_table :user_memories do |t|
  t.references :user
  t.references :entity
  t.string :memory_type  # 'preference', 'fact', 'goal', 'pattern'
  t.string :category     # 'communication', 'business', 'personal'
  t.text :content
  t.string :source       # 'conversation', 'explicit', 'inferred'
  t.float :confidence
  t.integer :access_count, default: 0
end
```

### ScoutLearning (AI Learning)

```ruby
create_table :scout_learnings do |t|
  t.references :entity
  t.string :learning_type  # 'tool_usage', 'delegation', 'error_recovery'
  t.text :learning
  t.string :context
  t.string :source
  t.float :confidence
  t.float :success_rate
  t.integer :apply_count, default: 0
end
```

## Configuration

### Scheduled Jobs (solid_queue.rake)

```ruby
{
  key: "nightly_learning",
  class_name: "NightlyLearningJob",
  schedule: "0 2 * * *",  # 2 AM daily
  queue: "low_priority"
},
{
  key: "memory_cleanup",
  class_name: "MemoryCleanupJob", 
  schedule: "0 3 * * *",  # 3 AM daily
  queue: "low_priority"
}
```

### Proactive Memory Settings

```ruby
# ProactiveMemoryJob
CACHE_PREFIX = "proactive_memory"
CACHE_TTL = 10.minutes
MIN_CONFIDENCE = 0.4

# Debounce in scout_controller
cache_key = "proactive_memory_trigger:#{session_id}"
Rails.cache.write(cache_key, true, expires_in: 30.seconds)
```

## Benefits

1. **Faster Response Times**: Pre-warmed memories eliminate on-demand fetching latency
2. **More Context-Aware**: Scout anticipates what memories might be relevant
3. **Continuous Learning**: Patterns are extracted and applied automatically
4. **Personalized Experience**: Scout adapts to each user's communication style
5. **Efficient Storage**: Summaries compress old conversations while preserving context
6. **Cross-Session Continuity**: Users can pick up conversations days/weeks later

## Monitoring

Check job status:
```bash
rake solid_queue:list_recurring
```

Manually trigger nightly learning:
```bash
rake solid_queue:trigger_task[nightly_learning]
```

View logs:
```bash
tail -f log/solid_queue_jobs.log | grep -E "(Proactive|Nightly|Memory)"
```
