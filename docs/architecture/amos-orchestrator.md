# AMOS Orchestrator Framework

## The Problem

Currently, AMOS is just an LLM with access to tools. He doesn't truly understand:
- What the platform can do
- When to handle something himself vs. delegate
- The current state of the system
- What's possible vs. what isn't built yet

**We need AMOS to be the intelligent brain of the entire platform.**

## The Vision

```
┌─────────────────────────────────────────────────────────────────────┐
│                           USER                                       │
│                             ↓                                        │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                      AMOS ORCHESTRATOR                       │   │
│  │                                                               │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │   │
│  │  │  KNOWLEDGE  │  │  ROUTING    │  │  PLATFORM   │          │   │
│  │  │  BASE       │  │  ENGINE     │  │  AWARENESS  │          │   │
│  │  │             │  │             │  │             │          │   │
│  │  │ • Agents    │  │ • Do it     │  │ • Health    │          │   │
│  │  │ • Tools     │  │ • Delegate  │  │ • Tickets   │          │   │
│  │  │ • Limits    │  │ • Escalate  │  │ • PRs       │          │   │
│  │  │ • Persona   │  │ • Create    │  │ • Anomalies │          │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘          │   │
│  │                             ↓                                 │   │
│  │           [INTELLIGENT ACTION SELECTION]                     │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                             ↓                                        │
│        ┌─────────────────────────────────────────────┐             │
│        │                EXECUTION                     │             │
│        ├─────────┬─────────┬─────────┬──────────────┤             │
│        │ Direct  │ Agent   │ Ticket  │ Human        │             │
│        │ Tool    │ Delega- │ Creat-  │ Escala-      │             │
│        │ Call    │ tion    │ ion     │ tion         │             │
│        └─────────┴─────────┴─────────┴──────────────┘             │
└─────────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Capability Registry

A structured definition of what's possible:

```ruby
# What AMOS can do directly (with tools)
DIRECT_CAPABILITIES = {
  "answer_questions" => { description: "Answer questions about the platform, user data, etc." },
  "search_documents" => { description: "Search knowledge base and documents" },
  "send_email" => { description: "Compose and send emails" },
  "manage_contacts" => { description: "Create, update, search contacts" },
  "create_ticket" => { description: "Report bugs or issues" },
  # ...
}

# What specialized agents can do
AGENT_CAPABILITIES = {
  "marketing_agent" => {
    capabilities: ["campaign_creation", "content_writing", "audience_analysis"],
    when_to_use: "Marketing tasks, campaigns, content generation"
  },
  "sales_agent" => {
    capabilities: ["lead_scoring", "pipeline_management", "deal_analysis"],
    when_to_use: "Sales-related tasks, lead management"
  },
  # ...
}

# What we can't do yet (be honest!)
NOT_YET_AVAILABLE = [
  "video_generation",
  "real_time_voice_calls",
  "direct_database_access",
  # ...
]
```

### 2. Routing Intelligence

Clear decision tree for AMOS:

```
User Request
     │
     ▼
┌────────────────────┐
│ Is this a simple   │──Yes──▶ AMOS answers directly
│ question/chat?     │
└────────┬───────────┘
         │ No
         ▼
┌────────────────────┐
│ Can a tool handle  │──Yes──▶ AMOS executes the tool
│ this directly?     │
└────────┬───────────┘
         │ No
         ▼
┌────────────────────┐
│ Is there a         │──Yes──▶ Delegate to that agent
│ specialized agent? │
└────────┬───────────┘
         │ No
         ▼
┌────────────────────┐
│ Is this a bug or   │──Yes──▶ Create support ticket
│ issue report?      │
└────────┬───────────┘
         │ No
         ▼
┌────────────────────┐
│ Is this critical/  │──Yes──▶ Escalate to human
│ sensitive?         │
└────────┬───────────┘
         │ No
         ▼
┌────────────────────┐
│ Can we build this? │──Yes──▶ "This isn't available yet,
└────────┬───────────┘         but I can create a feature request"
         │ No
         ▼
     "I'm sorry, this is outside
      what I can help with"
```

### 3. Platform Awareness

AMOS should have real-time access to:

```ruby
{
  platform_health: {
    overall_score: 0.95,
    active_agents: 5,
    success_rate_24h: 0.92,
    anomalies: 2,
    critical_tickets: 0
  },
  pending_actions: {
    tickets_open: 3,
    prs_pending: 1,
    approvals_needed: 0
  },
  recent_activity: {
    last_fix_merged: "2 hours ago",
    last_evolution_cycle: "1 hour ago",
    last_perception: "15 minutes ago"
  }
}
```

### 4. Dynamic System Prompt

The system prompt should be **generated dynamically** based on:
- Entity configuration
- Available agents for this entity
- Current platform state
- User's role and permissions

## AMOS's Identity

### Who is AMOS?

AMOS is not just an assistant - he is the **orchestrator of the entire platform**. He should:

1. **Be Honest** - Never claim to do something he can't
2. **Be Knowledgeable** - Know what's possible across the platform
3. **Be Decisive** - Know when to act vs. delegate vs. escalate
4. **Be Aware** - Understand the current state of things
5. **Be Helpful** - Always move toward the user's goal

### AMOS's Voice

- Professional but warm
- Concise but thorough when needed
- Confident but humble about limitations
- Proactive but not presumptuous

### What AMOS Says When He Can't Help

Instead of hallucinating or being vague:

❌ "I'll try to do that..." (when he can't)
❌ "Let me see..." (and then failing)

✅ "That's not something I can do directly, but I can [alternative]"
✅ "That feature isn't built yet. Would you like me to create a feature request?"
✅ "For that, I'd recommend working with [specific agent/person]"

## Implementation Plan

1. **CapabilityRegistry** - Central source of truth for what's possible
2. **AmosOrchestrator** - The brain that makes routing decisions
3. **SystemPromptBuilder** - Generates context-aware prompts
4. **PlatformStateService** - Provides real-time awareness
5. **DelegationService** - Handles handoff to agents

## The Goal

When this is complete, AMOS will be able to say:

> "I'm AMOS, the orchestrator of this platform. I know we have 5 specialized agents available to you, 47 tools I can use directly, and right now the platform is running at 95% health with 2 minor anomalies being investigated. How can I help you today?"

This is the difference between a chatbot and an **intelligent platform orchestrator**.


