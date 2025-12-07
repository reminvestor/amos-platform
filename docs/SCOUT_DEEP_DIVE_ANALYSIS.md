# Scout Deep Dive Analysis

**Branch:** `scout`  
**Date:** December 7, 2025  
**Purpose:** Comprehensive analysis of Scout's system prompt, tools, memory system, and decision-making framework to identify improvement opportunities.

---

## Table of Contents
1. [Architecture Overview](#1-architecture-overview)
2. [System Prompt Analysis](#2-system-prompt-analysis)
3. [Tools Available to Scout](#3-tools-available-to-scout)
4. [Memory System](#4-memory-system)
5. [Learning About User/Business](#5-learning-about-userbusiness)
6. [Decision Framework](#6-decision-framework-agent-vs-self)
7. [Key Issues Identified](#7-key-issues-identified)
8. [Recommendations](#8-recommendations)

---

## 1. Architecture Overview

### Core Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `ScoutController` | `app/controllers/scout_controller.rb` | Main controller - chat, streaming, session management |
| `ScoutGenericToolsServiceV2` | `app/services/scout_generic_tools_service_v2.rb` | **PRIMARY** - Handles ALL LLM interactions with tools |
| `Scout::MemoryTools` | `lib/scout/memory_tools.rb` | Redis-based extended conversation history |
| `ScoutMessage` | `app/models/scout_message.rb` | PostgreSQL message storage |
| `ScoutConversation` | `app/models/scout_conversation.rb` | Conversation tracking |
| `ScoutLoadoutConfiguration` | `app/models/scout_loadout_configuration.rb` | Per-entity tool configuration |
| `ToolCatalog` | `app/services/tools/tool_catalog.rb` | Tool registry and execution |
| `RagService` | `app/services/rag_service.rb` | Knowledge base search |

### Message Flow

```
User sends message
    ↓
ScoutController receives request
    ↓
save_scout_message() → PostgreSQL + Redis
    ↓
persisted_history_last_k(20) → Load active context window
    ↓
ScoutGenericToolsServiceV2.process_message_with_tools_streaming()
    ↓
BedrockService.send_message_streaming() with tools
    ↓
Tool execution (if needed)
    ↓
Response saved and streamed back to user
```

### Key Files

```
app/controllers/scout_controller.rb              # Main controller (3600+ lines)
app/services/scout_generic_tools_service_v2.rb   # Primary AI service (1500 lines)
app/models/scout_loadout_configuration.rb        # Tool allowlist config
lib/scout/memory_tools.rb                        # Redis memory management
app/services/rag_service.rb                      # Knowledge base
app/services/amos_ai/business_extractor.rb       # Business info extraction
app/models/business_insight.rb                   # Stored insights
```

---

## 2. System Prompt Analysis

**Location:** `ScoutGenericToolsServiceV2.build_system_prompt()` (lines 407-755)

### Current Structure

```
1. Identity: "You are Scout (powered by Amos), the AI business assistant"
2. Current date/time (for date-relative queries)
3. CRITICAL RULE: Use web_search for real-time data
4. YOUR CAPABILITIES section
5. PROACTIVE DECISION FRAMEWORK (6 levels)
6. NEVER DECLINE - ALWAYS ACT section
7. WEB SEARCH instructions
8. GROUNDING - VERIFY DON'T HALLUCINATE
9. DELEGATION FLOW
10. AGENT COMMUNICATION FRAMEWORK
11. Examples of good responses
12. CANVAS LOADING instructions
13. DOCUMENTS handling
14. CONTEXT AWARENESS
```

### System Prompt Strengths ✅

1. **Clear identity** - Scout knows who it is
2. **Current time awareness** - Can handle "today", "this week" queries
3. **Decision framework** - 6-level hierarchy for action selection
4. **Never decline attitude** - Platform can evolve to meet needs
5. **Web search emphasis** - Multiple reminders to use web_search
6. **Canvas awareness** - Knows current view context
7. **Document handling** - Clear instructions for file operations

### System Prompt Gaps ❌

1. **No memory tool instructions** - Memory tools exist but not mentioned in prompt
2. **No learned context section** - Business insights exist but not included
3. **No user preferences** - No personalization beyond basic profile
4. **RAG context is minimal** - Only enhanced message, not system prompt
5. **No conversation style preferences** - Doesn't remember how user likes to communicate
6. **Decision examples are limited** - Could use more nuanced examples

---

## 3. Tools Available to Scout

**Configuration:** `ScoutLoadoutConfiguration.DEFAULT_TOOL_ALLOWLIST`

### Current Tool Categories

| Category | Tools | Count |
|----------|-------|-------|
| **Data** | get_schema, get_data, create_object, update_object, update_landing_page_content | 5 |
| **Documents** | read_document, query_document_content, query_rag_store | 3 |
| **Canvas** | load_canvas, create_dynamic_visualization, save_visualization | 3 |
| **Memory** | retrieve_history, get_message_count, search_history | 3 |
| **Agents** | list_available_agents, delegate_to_agent, invoke_agent_plugin, update_agent, ask_agent_for_help, respond_to_agent | 6 |
| **Web** | web_search | 1 |
| **Integrations** | execute_integration, list_operations, list_connections, explain_query | 4 |
| **Scheduling** | create_scheduled_task, list_scheduled_tasks, manage_scheduled_task | 3 |
| **Workflow** | get_workflow_context, get_work_inbox | 2 |
| **Analysis** | analyze_dataset | 1 |

**Total: ~31 tools**

### Excluded Tools (Always Delegate)

```ruby
EXCLUDED_TOOLS = %w[
  generate_ai_landing_page
  process_landing_page_images
  analyze_landing_page_request
  generate_integration_scaffold
  generate_integration_code
  add_integration_endpoint
  test_integration_endpoint
  register_integration_operation
  manage_task_list
  create_agent
  create_tool
  update_tool
  create_integration
  create_integration_foundation
  configure_integration_auth
  test_integration_auth
  add_integration_operations
]
```

### Tool Issues Identified

1. **Memory tools not in system prompt** - Scout has them but may not know
2. **No tool for saving user preferences** - Can't persist learned info
3. **No tool for retrieving business insights** - Insights exist but not accessible
4. **Analyze dataset underutilized** - Powerful but not well-documented

---

## 4. Memory System

### Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: Active Context Window (20 messages)           │
│ Source: PostgreSQL via persisted_history_last_k(20)    │
│ Passed to: Every Bedrock AI request                    │
│ Token usage: ~10-15K tokens                            │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Layer 2: Redis Extended History (up to 1000 messages)  │
│ Keys: scout:{session_id}:messages                      │
│       scout:{session_id}:message_count                 │
│ TTL: 2 hours (configurable)                            │
│ Access: On-demand via memory tools                     │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Layer 3: PostgreSQL Permanent Storage                  │
│ Table: scout_messages                                  │
│ Indexed: session_id, user_id, created_at               │
│ Purpose: Analytics, exports, compliance                │
└─────────────────────────────────────────────────────────┘
```

### Memory Tools Available

**Tool:** `retrieve_history`
```ruby
{
  name: 'retrieve_history',
  description: 'Retrieve older conversation messages...',
  parameters: {
    start_index: 'integer',
    end_index: 'integer', 
    count: 'integer (default: 20)'
  }
}
```

**Tool:** `get_message_count`
```ruby
{
  name: 'get_message_count',
  description: 'Get the total number of messages...',
  parameters: {}
}
```

**Tool:** `search_history`
```ruby
{
  name: 'search_history',
  description: 'Search through conversation history...',
  parameters: {
    keywords: 'string (required)',
    role: 'user|assistant',
    max_results: 'integer (default: 10)'
  }
}
```

### Memory System Issues

1. **No system prompt guidance on memory tools** - Scout may not know when to use them
2. **No cross-session memory** - User preferences don't persist after 2 hours
3. **No semantic search of history** - Only keyword-based
4. **No summarization** - Old conversations not condensed
5. **Session isolation** - Can't reference previous sessions

---

## 5. Learning About User/Business

### Existing Infrastructure (Partially Implemented)

#### BusinessInsight Model

```ruby
# app/models/business_insight.rb
INSIGHT_TYPES = %w[
  company_info
  target_audience
  marketing_challenges
  industry_details
  contact_preferences
  tool_usage_patterns
  business_goals
  pain_points
]
```

#### BusinessExtractor Service

```ruby
# app/services/amos_ai/business_extractor.rb
def extract(conversation_context:)
  # Uses Claude to extract structured business information
  # Returns: { insights: [...], business_profile_updates: {...} }
end
```

#### RagService

```ruby
# app/services/rag_service.rb
def search(query, options = {})
  # Searches across:
  # - documents (knowledge_documents)
  # - conversations (conversation_embeddings)
  # - integrations (integration_embeddings)
end
```

### Current State: NOT FULLY CONNECTED

| Component | Exists? | Connected to Scout? | Notes |
|-----------|---------|---------------------|-------|
| BusinessInsight model | ✅ | ❌ | Insights stored but not used in prompt |
| BusinessExtractor | ✅ | ❌ | Can extract but not called during chat |
| RagService | ✅ | Partial | Only used in ScoutConversationWithToolsService (legacy) |
| ConversationEmbedding | ✅ | ❌ | Stores embeddings but not queried |
| Entity snapshot | ✅ | ✅ | Basic entity info in context |

### What Scout Actually Knows About User

Currently loaded via `enhance_message_with_canvas_context()`:
```ruby
user_context_prefix = "[User Context: #{user.first_name} #{user.last_name} from #{entity.name}]\n\n"
```

That's it. Very minimal.

### What Scout COULD Know

1. **Business Profile** - Industry, company size, target market
2. **Historical Insights** - Learned facts from past conversations
3. **User Preferences** - Communication style, timezone, expertise level
4. **Tool Usage Patterns** - Which tools they use most
5. **Past Conversations** - Key decisions and outcomes
6. **Document Knowledge** - What's in their uploaded files
7. **Integration Data** - Connected services and their state

---

## 6. Decision Framework (Agent vs Self)

### Current 6-Level Hierarchy (from system prompt)

```
1️⃣ DO I NEED CURRENT/REAL DATA?
   → Stock prices, weather, news → web_search
   → CRM data, contacts → get_data
   → Integration status → list_connections
   → Documents → query_document_content

2️⃣ CAN I DO THIS WITH MY TOOLS?
   → Data queries → get_data, get_schema
   → Web research → web_search
   → Visualizations → load_canvas + create_dynamic_visualization
   → Documents → read_document, query_document_content

3️⃣ IS THERE A SPECIALIST AGENT FOR THIS?
   → list_available_agents to see specialists
   → Landing pages → ai_landing_page_creator
   → Email campaigns → email_sequence_architect
   → Financial analysis → investment_research_analyst

4️⃣ SHOULD I CREATE A NEW AGENT?
   → Task is recurring and no agent exists
   → delegate to agent_architect

5️⃣ SHOULD I CREATE A NEW TOOL?
   → Need to connect to an API
   → delegate to tool_builder

6️⃣ ONLY THEN: Answer from knowledge
```

### Decision Framework Issues

1. **Memory tools not in hierarchy** - When should Scout check history?
2. **No examples for memory usage** - "What did I say about budget?"
3. **Level 3 vs 2 ambiguity** - When is something "too complex" for Scout?
4. **No fallback instructions** - What if agent delegation fails?

### Observed Behavior Problems

1. Scout sometimes tries to create landing pages directly instead of delegating
2. Scout doesn't use memory tools even when user references past conversations
3. Scout doesn't check RAG before answering general questions
4. Scout over-explains actions instead of just doing them

---

## 7. Key Issues Identified

### 🔴 Critical Issues

| Issue | Impact | Location |
|-------|--------|----------|
| Memory tools not in system prompt | Scout can't reference past conversations | `build_system_prompt()` |
| BusinessInsight not used | Scout doesn't learn about user over time | Missing integration |
| RAG context not in system prompt | Scout can't access knowledge base proactively | `enhance_message_with_canvas_context()` |

### 🟡 Moderate Issues

| Issue | Impact | Location |
|-------|--------|----------|
| No user preferences storage | Can't personalize responses | Missing functionality |
| Conversation truncation at 6 messages | Loss of recent context for tools | `format_conversation_for_ai()` |
| No cross-session memory | User has to re-explain things | Redis TTL + no persistent store |
| Decision framework examples limited | Scout makes wrong delegation choices | `build_system_prompt()` |

### 🟢 Minor Issues

| Issue | Impact | Location |
|-------|--------|----------|
| Over-verbose responses | Token usage, user experience | Prompt style instructions |
| Canvas loading narration | Unnecessary chatter | Prompt instructions |
| Tool descriptions could be clearer | LLM might misuse tools | Individual tool files |

---

## 8. Recommendations

### Phase 1: Quick Wins (System Prompt Fixes)

#### 1.1 Add Memory Tool Instructions to System Prompt

```ruby
# Add after "YOUR CAPABILITIES" section:
CONVERSATION MEMORY:
You have access to extended conversation history beyond your active context window:
- Use get_message_count to see how many messages exist
- Use retrieve_history to get older messages when user references something not in context
- Use search_history to find specific topics discussed earlier

Examples:
- User: "What did I say about the budget earlier?" → search_history(keywords: "budget")
- User: "Summarize our initial conversation" → retrieve_history(start_index: 1, end_index: 20)
- User: "How long have we been talking?" → get_message_count()
```

#### 1.2 Add Learned Context Section

```ruby
# Add near the beginning of system prompt, after identity:
KNOWN ABOUT THIS USER/BUSINESS:
#{format_business_insights_for_prompt(entity)}
#{format_user_preferences_for_prompt(user)}
```

#### 1.3 Clarify Decision Framework with Memory

```
0️⃣ SHOULD I CHECK MEMORY FIRST?
   → User references something from earlier → search_history
   → User asks "what did I/we say about X" → search_history  
   → You need context not in active window → retrieve_history
```

### Phase 2: Memory System Improvements

#### 2.1 Add Cross-Session Memory

Create a new table/model for persistent user facts:

```ruby
# app/models/user_memory.rb
class UserMemory < ApplicationRecord
  belongs_to :user
  belongs_to :entity
  
  # Types: preference, fact, decision, goal
  validates :memory_type, presence: true
  validates :content, presence: true
  validates :confidence, numericality: { in: 0..1 }
  
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :high_confidence, -> { where("confidence >= 0.7") }
end
```

#### 2.2 Create Memory Extraction Job

Run after each conversation to extract and store learnings:

```ruby
# app/jobs/extract_user_memories_job.rb
class ExtractUserMemoriesJob < ApplicationJob
  def perform(session_id)
    # Use BusinessExtractor to analyze conversation
    # Store as UserMemory records
    # Update BusinessProfile if needed
  end
end
```

### Phase 3: Business Context Integration

#### 3.1 Load Business Insights into System Prompt

```ruby
def format_business_insights_for_prompt(entity)
  insights = BusinessInsight.where(entity: entity)
                           .high_confidence
                           .recent
                           .limit(10)
  
  return "" if insights.empty?
  
  insights.map { |i| "- #{i.insight_type.humanize}: #{i.content}" }.join("\n")
end
```

#### 3.2 Add User Preferences to Context

```ruby
def format_user_preferences_for_prompt(user)
  prefs = UserMemory.where(user: user, memory_type: 'preference')
                    .high_confidence
  
  return "" if prefs.empty?
  
  prefs.map { |p| "- #{p.content}" }.join("\n")
end
```

### Phase 4: Decision Framework Enhancement

#### 4.1 Add More Decision Examples

```
COMMON TASK ROUTING:

SCOUT HANDLES DIRECTLY:
• "Show me my campaigns" → load_canvas + get_data
• "How many contacts do I have?" → get_data
• "What's the current price of AAPL?" → web_search
• "What did we discuss yesterday?" → search_history
• "Explain this document" → read_document + respond

DELEGATE TO AGENTS:
• "Create a landing page" → ai_landing_page_creator
• "Build an email campaign" → email_sequence_architect
• "Connect to Stripe" → integration_architect
• "Analyze my sales trends" → analytics_agent (if complex)
• "Import these contacts" → data_agent

WHEN IN DOUBT: If task requires multiple steps of creation/generation → DELEGATE
```

### Implementation Priority

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| 1 | Add memory tool instructions to prompt | Low | High |
| 2 | Load business insights into prompt | Medium | High |
| 3 | Add decision examples | Low | Medium |
| 4 | Create UserMemory model | Medium | High |
| 5 | Integrate BusinessExtractor | Medium | Medium |
| 6 | Add user preferences tool | Medium | Medium |

---

## Appendix: Key Code References

### System Prompt Location
```
app/services/scout_generic_tools_service_v2.rb
  → build_system_prompt() (lines 407-755)
```

### Tool Configuration
```
app/models/scout_loadout_configuration.rb
  → DEFAULT_TOOL_ALLOWLIST (lines 18-50)
  → EXCLUDED_TOOLS (lines 53-71)
```

### Memory Tools
```
lib/scout/memory_tools.rb
app/services/tools/retrieve_history_tool.rb
app/services/tools/get_message_count_tool.rb
app/services/tools/search_history_tool.rb
```

### Business Learning
```
app/models/business_insight.rb
app/services/amos_ai/business_extractor.rb
app/services/rag_service.rb
```

### Message Flow
```
app/controllers/scout_controller.rb
  → chat() (line 65)
  → chat_streaming() (line 452)
  → save_scout_message() (line 2025)
  → persisted_history_last_k() (line 2011)
```
