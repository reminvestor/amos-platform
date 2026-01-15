# Write Plan

Create atomic, executable task breakdowns for features.

## Usage

```
/write-plan [feature description]
```

## What It Does

Breaks down a feature into bite-sized tasks (2-5 minutes each) organized into logical phases.

## Task Size Rule

**Each task should take 2-5 minutes.** If it would take longer, break it down further.

## Plan Structure

Plans follow this AMOS-specific structure:

```markdown
## Feature: [Name]

### Phase 1: Database
- [ ] Create migration (3 min)
- [ ] Add indexes (2 min)
- [ ] Verify schema (2 min)

### Phase 2: Model
- [ ] Create model with validations (5 min)
- [ ] Add associations (3 min)
- [ ] Entity scoping (3 min)
- [ ] Model tests (5 min)

### Phase 3: Service Layer
- [ ] Create service class (5 min)
- [ ] Implement methods (5 min)
- [ ] Service tests (5 min)

### Phase 4: Scout Tool
- [ ] Create tool class (5 min)
- [ ] Define parameters (3 min)
- [ ] Implement execute (5 min)
- [ ] Tool tests (3 min)

### Phase 5: Integration
- [ ] Verify in ToolCatalog (2 min)
- [ ] Test via Scout chat (5 min)
- [ ] Entity isolation test (3 min)

### Phase 6: Polish
- [ ] Full test suite (3 min)
- [ ] Rubocop (2 min)
- [ ] Cleanup (2 min)
```

## Output

A detailed plan with:
- Phases grouping related tasks
- Time estimates for each task
- Checkbox format for tracking
- AMOS patterns included (entity scoping, tools, etc.)

## Next Steps

After writing a plan:
- `/execute-plan` - Start systematic execution
- Use TodoWrite tool to track progress

## Examples

```
/write-plan subscription management with Stripe
/write-plan webhook processing for external events
/write-plan campaign analytics dashboard
```

## Related

- [Planning and Brainstorming Skill](../.claude/skills/planning-and-brainstorming/SKILL.md)
- `/brainstorm` - Clarify requirements first
- `/execute-plan` - Execute the plan
