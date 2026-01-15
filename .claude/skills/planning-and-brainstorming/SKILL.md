# Planning and Brainstorming

Interactive design refinement and structured task breakdown for complex features.

## Description

This skill provides three complementary modes for tackling complex development work:
1. **Brainstorm** - Socratic questioning to refine requirements and explore approaches
2. **Write Plan** - Break work into bite-sized 2-5 minute tasks
3. **Execute Plan** - Systematic execution with checkpoints and verification

Based on battle-tested patterns from [obra/superpowers](https://github.com/obra/superpowers).

**Use this skill when:**
- Starting a complex feature that needs clarification
- Breaking down large tasks into manageable steps
- Need to explore multiple implementation approaches
- Want structured execution with progress tracking

## Instructions

### Mode 1: Brainstorm (`/brainstorm`)

**Purpose:** Refine requirements through interactive questioning.

**How it works:**
- Present your idea or problem
- Receive probing questions to clarify scope
- Explore trade-offs and alternatives
- Arrive at a clear, well-defined specification

**Brainstorm Questions Framework:**

1. **Scope Questions:**
   - What's the minimum viable version?
   - What's explicitly out of scope?
   - Who are the users of this feature?

2. **Technical Questions:**
   - How does this integrate with existing components?
   - What are the performance requirements?
   - Are there security considerations?

3. **Edge Case Questions:**
   - What happens when X fails?
   - How should multi-tenant scoping work?
   - What are the error states?

4. **Trade-off Questions:**
   - Build vs. buy/integrate?
   - Synchronous vs. background job?
   - Simple now vs. flexible later?

**Example Brainstorm Session:**

```markdown
User: "I want to add subscription billing"

Questions:
1. What billing provider? (Stripe, custom, both?)
2. What plans? (Fixed tiers, usage-based, hybrid?)
3. Who manages subscriptions? (Admin only, self-service?)
4. What happens on failed payment? (Grace period, immediate lock?)
5. Need trial periods?
6. Multi-currency support?

After clarification:
- Stripe integration
- 3 fixed tiers (free, pro, enterprise)
- Self-service with admin override
- 7-day grace period on failures
- 14-day free trial
- USD only for v1
```

### Mode 2: Write Plan (`/write-plan`)

**Purpose:** Create atomic, executable task lists.

**Task Size Rule:** Each task should take 2-5 minutes. If longer, break it down further.

**Plan Structure:**

```markdown
## Feature: [Name]

### Phase 1: Foundation
- [ ] Task 1.1: [Description] (2 min)
- [ ] Task 1.2: [Description] (3 min)

### Phase 2: Core Implementation
- [ ] Task 2.1: [Description] (5 min)
- [ ] Task 2.2: [Description] (3 min)

### Phase 3: Integration
- [ ] Task 3.1: [Description] (2 min)

### Phase 4: Testing & Verification
- [ ] Task 4.1: [Description] (5 min)
- [ ] Task 4.2: [Description] (3 min)

### Phase 5: Cleanup
- [ ] Task 5.1: [Description] (2 min)
```

**AMOS-Specific Plan Template:**

```markdown
## Feature: Subscription Management

### Phase 1: Database (10 min total)
- [ ] Create migration for subscriptions table (3 min)
- [ ] Add entity foreign key and indexes (2 min)
- [ ] Run migration (2 min)
- [ ] Verify schema in console (3 min)

### Phase 2: Model (15 min total)
- [ ] Create Subscription model with validations (5 min)
- [ ] Add belongs_to :entity association (2 min)
- [ ] Add entity scoping scope (3 min)
- [ ] Write model tests (5 min)

### Phase 3: Service Layer (15 min total)
- [ ] Create SubscriptionService for business logic (5 min)
- [ ] Implement create/update/cancel methods (5 min)
- [ ] Write service tests (5 min)

### Phase 4: Scout Tool (15 min total)
- [ ] Create ManageSubscriptionTool extending BaseTool (5 min)
- [ ] Define tool parameters (3 min)
- [ ] Implement execute method (5 min)
- [ ] Write tool tests (2 min)

### Phase 5: Integration (10 min total)
- [ ] Verify tool in ToolCatalog (2 min)
- [ ] Test via Scout chat interface (5 min)
- [ ] Check entity scoping isolation (3 min)

### Phase 6: Polish (5 min total)
- [ ] Run full test suite (2 min)
- [ ] Run rubocop (2 min)
- [ ] Clean up any debug code (1 min)
```

### Mode 3: Execute Plan (`/execute-plan`)

**Purpose:** Systematic execution with checkpoints.

**Execution Rules:**

1. **Work in batches** - Complete 3-5 tasks, then checkpoint
2. **Verify each phase** - Run tests before moving to next phase
3. **Commit incrementally** - Don't wait until the end
4. **Document blockers** - Note issues for later resolution

**Checkpoint Template:**

```markdown
## Checkpoint: After Phase 2

**Completed:**
- [x] Created subscriptions migration
- [x] Added model with validations
- [x] Entity scoping implemented

**Verified:**
- [x] Migration ran successfully
- [x] Model tests pass (4/4)
- [x] Console shows correct associations

**Blockers:**
- None

**Next Phase:** Service Layer

**Commit:** "Add Subscription model with entity scoping"
```

**Batch Execution Flow:**

```
┌─────────────────────────────────────────────┐
│  1. Pick 3-5 tasks from plan                │
│  2. Execute tasks                           │
│  3. Run relevant tests                      │
│  4. Create checkpoint                       │
│  5. Commit if appropriate                   │
│  6. Repeat until phase complete             │
│  7. Final phase verification                │
│  8. Move to next phase                      │
└─────────────────────────────────────────────┘
```

### Combining Modes

**Recommended Flow for Complex Features:**

```
/brainstorm "subscription billing"
   ↓ (requirements clarified)
/write-plan "subscription billing with Stripe"
   ↓ (tasks broken down)
/execute-plan
   ↓ (systematic implementation)
Done!
```

## Examples

**Brainstorm a feature:**
```
Use planning-and-brainstorming skill mode=brainstorm for "real-time notifications"
```

**Create a plan:**
```
Use planning-and-brainstorming skill mode=plan for "webhook processing system"
```

**Execute existing plan:**
```
Use planning-and-brainstorming skill mode=execute
```

**Full workflow:**
```
Use planning-and-brainstorming skill for "add audit logging to all tools"
```

## Commands

Create corresponding slash commands in `.claude/commands/`:

- `/brainstorm [topic]` - Start brainstorming session
- `/write-plan [feature]` - Create execution plan
- `/execute-plan` - Begin/continue plan execution

## Resources

- [Starting Features](../starting-features/SKILL.md) - GitHub issue workflow
- [Test-Driven Development](../test-driven-development/SKILL.md) - TDD during execution
- [Complete Feature](../../commands/complete-feature.md) - End-to-end workflow
