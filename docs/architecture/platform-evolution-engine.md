# Platform Evolution Engine

## Overview

The Platform Evolution Engine is an **external module** that enables the AMOS platform to truly evolve and improve itself over time. It operates outside the main application to ensure:

1. **Independence**: Can fix issues even if the main platform crashes
2. **Safety**: Code modifications happen in isolation with human approval
3. **Continuous Improvement**: Automatically learns from errors and user feedback

## Core Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PLATFORM EVOLUTION ENGINE                        │
│                   (Runs Separately from Main App)                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │   LOG MONITOR   │    │  TICKET SYSTEM  │    │  DEBUG AGENT    │ │
│  │                 │    │                 │    │                 │ │
│  │ • Watch logs    │    │ • User tickets  │    │ • Analyze issue │ │
│  │ • Detect errors │───▶│ • Auto-tickets  │───▶│ • Gather info   │ │
│  │ • Pattern match │    │ • Priority calc │    │ • Propose fixes │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│                                                        │            │
│                                                        ▼            │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │  HUMAN REVIEW   │◀───│   PR MANAGER    │◀───│  CODE FIX AGENT │ │
│  │                 │    │                 │    │                 │ │
│  │ • Approve/Deny  │    │ • Create branch │    │ • Write fix     │ │
│  │ • Modify fix    │    │ • Submit PR     │    │ • Run tests     │ │
│  │ • Merge to main │    │ • Track status  │    │ • Validate      │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### 1. Error Detection Flow
```
Logs → Log Monitor → Auto-Ticket → Debug Agent → Code Fix → PR → Human Approval → Merge
```

### 2. User Ticket Flow
```
User → "Hey AMOS, I found a bug" → AMOS creates ticket → Debug Agent → Interactive Debug Session → Code Fix → PR → Human Approval → Merge
```

## Models

### SupportTicket
- `id`, `entity_id`, `user_id`
- `title`, `description`
- `source` (user_reported, amos_detected, log_monitor, scheduled_scan)
- `status` (open, investigating, fixing, pr_submitted, resolved, closed, wont_fix)
- `priority` (low, medium, high, critical)
- `category` (bug, performance, feature_request, security, data_issue)
- `error_signature` (for deduplication)
- `stack_trace`, `context_data`
- `assigned_to` (agent or human)

### DebugSession
- `id`, `support_ticket_id`
- `status` (gathering_info, analyzing, proposing_fix, awaiting_approval)
- `conversation_history` (JSONB - debug conversation with user/agent)
- `findings` (JSONB - what was discovered)
- `root_cause` (text analysis)
- `proposed_fixes` (JSONB - array of possible solutions)
- `selected_fix_index`
- `confidence_score`

### CodeFix
- `id`, `debug_session_id`
- `status` (drafting, testing, validated, rejected, applied)
- `files_modified` (JSONB - array of {path, original, modified})
- `test_results` (JSONB)
- `validation_notes`
- `git_branch`, `git_commit_sha`

### PullRequestSubmission
- `id`, `code_fix_id`
- `pr_number`, `pr_url`
- `status` (pending, approved, changes_requested, merged, closed)
- `reviewer_notes`
- `merged_at`, `merged_by`

## Safety Rails

### Phase 1 (Current - Human Approval Required)
- All PRs require human approval
- Changes are tested in staging first
- Rollback plan for every merge

### Phase 2 (Future - Gradual Autonomy)
- Low-risk fixes (typos, logging, docs) can auto-merge
- Medium-risk fixes need 1 human approval
- High-risk fixes need 2+ approvals

### Phase 3 (Future - Full Autonomy)
- System learns what fixes are safe
- Human approval only for novel situations
- Self-healing becomes default

## Integration Points

### With AMOS (Main Assistant)
- Tool: `create_support_ticket` - Users can report issues via chat
- Tool: `check_ticket_status` - Users can ask about their tickets
- Tool: `participate_in_debug` - AMOS can help gather info

### With Agent Lightning
- Failed agent executions auto-create tickets
- Successful fixes improve agent prompts

### With Living Platform
- Perception detects issues → creates tickets
- Evolution incorporates fixes into improvement cycles

## Deployment Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        PRODUCTION                                 │
│                                                                   │
│  ┌─────────────────┐           ┌─────────────────────────────┐  │
│  │  Main Platform  │           │  Evolution Engine           │  │
│  │  (Rails App)    │◀─────────▶│  (Separate Process/Service) │  │
│  │                 │   Shared   │                             │  │
│  │  • User facing  │   Redis    │  • Log monitoring          │  │
│  │  • AMOS chat    │     +      │  • Ticket processing       │  │
│  │  • API          │   DB       │  • Code fixing             │  │
│  └─────────────────┘           └─────────────────────────────┘  │
│                                          │                       │
│                                          ▼                       │
│                               ┌─────────────────┐               │
│                               │    GitHub       │               │
│                               │    (PRs)        │               │
│                               └─────────────────┘               │
└──────────────────────────────────────────────────────────────────┘
```

## Why This Makes Us a "Living Organism"

1. **Self-Healing**: Errors are detected and fixed automatically
2. **Learning**: Each fix improves the system's understanding
3. **User Feedback Loop**: User issues become improvements
4. **Model Agnostic**: As new AI models emerge, the fixer uses them
5. **Compound Growth**: Every fix makes future fixes easier

This is the missing piece that transforms AMOS from a static platform into a system that genuinely gets better every day.


