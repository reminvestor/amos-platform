# /cancel-ralph Command

Cancel an active Ralph Wiggum loop.

## Usage

```
/cancel-ralph
```

## What This Command Does

Terminates an active Ralph loop by removing the state file.

## Instructions

1. Check if a Ralph loop is active:
   ```bash
   test -f .claude/ralph-loop.local.md && echo "Loop active" || echo "No active loop"
   ```

2. If active, read the current iteration:
   ```bash
   grep '^iteration:' .claude/ralph-loop.local.md
   ```

3. Remove the state file to cancel:
   ```bash
   rm -f .claude/ralph-loop.local.md
   ```

4. Confirm cancellation to the user with the iteration count.

## Example Output

```
Cancelled Ralph loop (was at iteration 7)
```

Or if no loop is active:

```
No active Ralph loop found.
```

## When to Use

- Loop is stuck or not making progress
- Requirements changed mid-loop
- Need to manually review intermediate work
- Emergency stop needed

## Related Commands

- `/ralph-loop` - Start a new Ralph loop
