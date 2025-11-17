# Amos Architecture Overview

## Core Concept

Amos is a lightweight orchestrator that manages conversations and delegates complex work to specialized agents. Think of it as a conductor of an orchestra - it doesn't play the instruments, it coordinates the musicians.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                        │
│                    (Chat, Voice, API, etc.)                   │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      AMOS ORCHESTRATOR                        │
│  ┌─────────────┬──────────────┬────────────┬─────────────┐  │
│  │   Intent    │  Context     │   Job      │  Response   │  │
│  │  Analysis   │ Management   │  Manager   │   Buffer    │  │
│  └─────────────┴──────────────┴────────────┴─────────────┘  │
│                                                               │
│  Minimal Tools:                                               │
│  • Conversation Summary  • Entity Info  • Job Status         │
│  • Web Search           • RAG Query                          │
└───────────────────────────┬─────────────────────────────────┘
                            │
                  ┌─────────┴─────────┬─────────┬────────┐
                  ▼                   ▼         ▼        ▼
         ┌──────────────┐   ┌──────────────┐  ┌──────────────┐
         │  Landing Page │   │    Email     │  │ Integration  │
         │    Agent      │   │    Agent     │  │    Agent     │
         └──────────────┘   └──────────────┘  └──────────────┘
                │                   │                  │
                └───────────────────┴──────────────────┘
                                    │
                            ┌───────▼────────┐
                            │  Background    │
                            │  Job Queue     │
                            │ (SolidQueue)   │
                            └────────────────┘
```

## Key Components

### 1. Amos::Orchestrator
The brain of the system. Responsibilities:
- Analyze user intent (simple vs complex)
- Maintain conversation context
- Delegate complex tasks to agents
- Buffer and order responses
- Handle job lifecycle

### 2. Amos::ConversationContext
Maintains state across the conversation:
- Recent messages
- Active jobs
- Entity information
- User preferences
- Workflow states

### 3. Amos::JobManager
Manages the lifecycle of background jobs:
- Create jobs for agents
- Track job status
- Handle job communication
- Process job results

### 4. Amos::ResponseBuffer
Intelligently manages responses:
- Buffer responses from multiple sources
- Order by priority
- Merge related responses
- Ensure coherent conversation flow

### 5. Specialized Agents (e.g., LandingPageAgent)
Domain-specific workers that:
- Execute complex multi-step tasks
- Stream progress back to Amos
- Request user input when needed
- Handle their own error recovery

## Data Flow

1. **User Message** → Amos Orchestrator
2. **Intent Analysis** → Simple or Complex?
3. **Simple Query** → Handle directly with minimal tools
4. **Complex Task** → Delegate to specialized agent
5. **Agent Execution** → Streams updates back to Amos
6. **Response Buffer** → Orders and merges responses
7. **User Interface** → Receives coherent stream

## Benefits

### 1. **Separation of Concerns**
- Amos handles orchestration
- Agents handle domain logic
- UI stays simple

### 2. **Scalability**
- Easy to add new agent types
- Agents can run on separate workers
- Horizontal scaling of job processing

### 3. **Maintainability**
- Controller reduced from 2700+ lines to ~100
- Each agent is self-contained
- Clear interfaces between components

### 4. **Flexibility**
- Agents can use any tools they need
- Amos only has minimal tools
- Easy to swap implementations

### 5. **User Experience**
- Consistent response handling
- Better error recovery
- Non-blocking operations

## Tool Philosophy

### Amos (Minimal Tools)
- **Purpose**: State management and simple queries
- **Tools**:
  - Conversation summary
  - Entity information lookup
  - Job status checking
  - Web search (for current info)
  - RAG query (for knowledge base)

### Agents (Full Tool Access)
- **Purpose**: Execute complex domain tasks
- **Tools**: Whatever they need!
  - Database operations
  - API integrations
  - File processing
  - Email sending
  - Payment processing
  - etc.

## Migration Strategy

### Phase 1: Wrapper
1. Create Amos as a wrapper around existing logic
2. Keep ScoutController working as-is
3. Gradually move logic to Amos

### Phase 2: Agent Creation
1. Identify distinct domains (landing pages, email, etc.)
2. Create specialized agents for each
3. Move domain logic from services to agents

### Phase 3: Full Migration
1. Replace ScoutController with AmosController
2. Remove old parallel processing system
3. Unify all interactions through Amos

## Example Usage

```ruby
# User: "Create a landing page for my new product"

# 1. Amos analyzes intent
#    → Complex task, needs LandingPageAgent

# 2. Creates job
job = JobManager.create_job(
  agent: :landing_page_agent,
  task: "Create a landing page for my new product",
  context: context.snapshot
)

# 3. LandingPageAgent executes
#    → Streams: "I'll help you create a landing page..."
#    → Requests: "What's your product name?"
#    → User responds
#    → Creates page
#    → Streams: "Your page is ready!"

# 4. Amos handles all streaming
#    → Buffers responses
#    → Ensures proper ordering
#    → Delivers to user
```

## Future Enhancements

1. **Agent Collaboration**
   - Agents can create sub-jobs for other agents
   - Complex workflows across multiple agents

2. **Learning System**
   - Amos learns user preferences
   - Improves intent detection over time

3. **Plugin Architecture**
   - Third-party agent development
   - Marketplace for specialized agents

4. **Advanced Scheduling**
   - Priority queues
   - Resource-based scheduling
   - Cost optimization

## Conclusion

Amos represents a fundamental shift from monolithic to orchestrated architecture. By separating orchestration from execution, we achieve:
- Cleaner code
- Better scalability
- Improved user experience
- Easier maintenance
- Infinite extensibility

The key insight: **Amos doesn't do the work, it ensures the work gets done well.**

