# /ralph-loop Command

Start a Ralph Wiggum loop for iterative, autonomous AI development.

## Usage

```
/ralph-loop "<PROMPT>" [--max-iterations N] [--completion-promise "TEXT"]
```

## What This Command Does

Implements the **Ralph Wiggum technique** - a self-referential AI loop where:

1. You provide a task prompt once
2. Claude works on the task
3. On exit, the Stop hook intercepts and feeds the same prompt back
4. Claude reads its previous work from files/git and continues
5. Loop continues until completion promise is detected or max iterations reached

## Options

- `--max-iterations <n>` - Stop after N iterations (safety net, recommended)
- `--completion-promise "<text>"` - Phrase to output when done (wrapped in `<promise>` tags)

## Examples

```bash
# Simple task with iteration limit
/ralph-loop "Build a todo REST API with tests" --max-iterations 20

# Task with completion detection
/ralph-loop "Implement user authentication with tests. Output <promise>COMPLETE</promise> when all tests pass." --completion-promise "COMPLETE" --max-iterations 30

# TDD workflow
/ralph-loop "Build a payment service following TDD:
1. Write failing tests first
2. Implement minimal code to pass
3. Refactor as needed
4. Repeat until all requirements met

Requirements:
- Process payments via Stripe
- Handle errors gracefully
- 90%+ test coverage

Output <promise>DONE</promise> when complete." --completion-promise "DONE" --max-iterations 50
```

## How to Exit the Loop

1. **Completion Promise**: Output `<promise>YOUR_PHRASE</promise>` matching your `--completion-promise`
2. **Max Iterations**: Automatically stops after reaching the limit
3. **Manual Cancel**: Run `/cancel-ralph` in a new session

## Best Practices

### 1. Always Use Safety Limits
```
/ralph-loop "Task" --max-iterations 20
```

### 2. Clear Success Criteria
Include specific, measurable completion criteria:
```
When complete:
- All tests passing
- No linter errors
- README documented
```

### 3. TDD Workflow
The Ralph loop excels at test-driven development where tests provide automatic verification.

### 4. Break Complex Tasks
For large features, use phases:
```
Phase 1: Database models (test first)
Phase 2: API endpoints (test first)
Phase 3: Integration tests
```

## Instructions

Execute the setup script to initialize the Ralph loop:

1. Run the setup script with the provided arguments:
   ```bash
   $CLAUDE_PROJECT_DIR/.claude/commands/scripts/setup-ralph-loop.sh <args>
   ```

2. After setup, immediately begin working on the task described in the prompt.

3. The Stop hook will automatically intercept session exit and continue the loop.

**CRITICAL**: Only output the completion promise when the task is GENUINELY complete. Do NOT lie to escape the loop.

## Monitor Progress

```bash
# Check current iteration
grep '^iteration:' .claude/ralph-loop.local.md

# View full state
head -10 .claude/ralph-loop.local.md
```

## When to Use Ralph Loops

**Good for:**
- Test-driven development
- Well-defined tasks with clear success criteria
- Greenfield projects
- Tasks with automatic verification (tests, linters)

**Not good for:**
- Tasks requiring human judgment
- Design decisions
- Unclear requirements
- Production debugging

## Related Commands

- `/cancel-ralph` - Stop an active Ralph loop
