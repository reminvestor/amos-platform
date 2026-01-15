# Brainstorm

Interactive design refinement through Socratic questioning.

## Usage

```
/brainstorm [topic or feature idea]
```

## What It Does

Starts an interactive brainstorming session to:
1. Clarify requirements through probing questions
2. Explore implementation approaches
3. Identify edge cases and trade-offs
4. Arrive at a well-defined specification

## Questioning Framework

The brainstorm will explore:

**Scope:**
- What's the minimum viable version?
- What's explicitly out of scope?
- Who are the users?

**Technical:**
- How does it integrate with existing AMOS components?
- Performance requirements?
- Security considerations?

**Edge Cases:**
- Error states and handling?
- Multi-tenant scoping?
- External API failure modes?

**Trade-offs:**
- Build vs. integrate?
- Sync vs. async?
- Simple now vs. flexible later?

## Output

After brainstorming, you'll have:
- Clear feature specification
- Defined scope boundaries
- Identified technical approach
- List of edge cases to handle

## Next Steps

After brainstorming, use:
- `/write-plan` - Break into executable tasks
- `/feature` - Start GitHub issue workflow

## Examples

```
/brainstorm subscription billing
/brainstorm real-time notifications for workflow completion
/brainstorm multi-language support for landing pages
```

## Related

- [Planning and Brainstorming Skill](../.claude/skills/planning-and-brainstorming/SKILL.md)
- `/write-plan` - Create task breakdown
- `/execute-plan` - Systematic execution
