# Execute Plan

Systematic plan execution with checkpoints and verification.

## Usage

```
/execute-plan
```

## What It Does

Executes a previously created plan (from `/write-plan`) with:
1. Batch execution (3-5 tasks at a time)
2. Phase verification with tests
3. Checkpoint creation
4. Incremental commits

## Execution Flow

```
Pick 3-5 tasks → Execute → Test → Checkpoint → Commit → Repeat
```

## Checkpoint Template

After each batch, create a checkpoint:

```markdown
## Checkpoint: After Phase 2

**Completed:**
- [x] Created migration
- [x] Added model with validations
- [x] Entity scoping implemented

**Verified:**
- [x] Migration ran successfully
- [x] Tests pass (4/4)
- [x] Console verification done

**Blockers:**
- None (or list issues)

**Next:** Phase 3 - Service Layer

**Commit:** "Add Subscription model with entity scoping"
```

## Rules

1. **Work in batches** - Don't try to complete everything at once
2. **Verify each phase** - Run tests before moving forward
3. **Commit incrementally** - Small, focused commits
4. **Document blockers** - Note issues for later
5. **Use TDD** - Write tests as you implement

## Commands to Use During Execution

```bash
# Run tests for verification
/run-tests affected

# Check for linting issues
/rubocop

# Docker operations
/docker

# If stuck, debug systematically
Use systematic-debugging skill
```

## Examples

```
/execute-plan
```

(Assumes a plan was previously created with `/write-plan`)

## Related

- [Planning and Brainstorming Skill](../.claude/skills/planning-and-brainstorming/SKILL.md)
- `/write-plan` - Create the plan first
- `/run-tests` - Verify during execution
- [TDD Skill](../.claude/skills/test-driven-development/SKILL.md)
