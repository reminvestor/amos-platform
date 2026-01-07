#!/bin/bash
# ralph-wiggum-hook.sh - Stop hook for Ralph Wiggum self-referential loops
#
# This hook intercepts session exit when a Ralph loop is active, feeding
# the same prompt back to Claude to enable iterative, autonomous work.

STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/ralph-loop.local.md"
TRANSCRIPT_FILE="${CLAUDE_TRANSCRIPT:-}"

# If no ralph loop is active, allow normal exit
if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

# Read state file frontmatter
extract_field() {
    local field="$1"
    grep "^${field}:" "$STATE_FILE" | head -1 | sed "s/^${field}: *//" | tr -d '"'
}

iteration=$(extract_field "iteration")
max_iterations=$(extract_field "max_iterations")
completion_promise=$(extract_field "completion_promise")

# Validate numeric fields
if ! [[ "$iteration" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid iteration count in state file. Cleaning up." >&2
    rm -f "$STATE_FILE"
    exit 0
fi

if [[ -n "$max_iterations" ]] && ! [[ "$max_iterations" =~ ^[0-9]+$ ]]; then
    max_iterations=0
fi

# Extract prompt from state file (everything after the frontmatter)
prompt=$(awk '/^---$/{count++; next} count==2{print}' "$STATE_FILE")

if [[ -z "$prompt" ]]; then
    echo "Error: No prompt found in state file. Cleaning up." >&2
    rm -f "$STATE_FILE"
    exit 0
fi

# Check for completion promise in transcript
if [[ -n "$completion_promise" ]] && [[ -n "$TRANSCRIPT_FILE" ]] && [[ -f "$TRANSCRIPT_FILE" ]]; then
    # Get the last assistant message from the transcript
    last_message=$(tail -20 "$TRANSCRIPT_FILE" 2>/dev/null | grep '"role":"assistant"' | tail -1)

    # Check if completion promise is present
    if echo "$last_message" | grep -q "<promise>$completion_promise</promise>"; then
        echo ""
        echo "Ralph loop completed! Completion promise detected."
        echo "Total iterations: $iteration"
        rm -f "$STATE_FILE"
        exit 0
    fi
fi

# Check max iterations
if [[ "$max_iterations" -gt 0 ]] && [[ "$iteration" -ge "$max_iterations" ]]; then
    echo ""
    echo "Ralph loop reached maximum iterations ($max_iterations)."
    echo "Loop terminated. Use /ralph-loop to start a new one."
    rm -f "$STATE_FILE"
    exit 0
fi

# Increment iteration counter
new_iteration=$((iteration + 1))
sed -i.bak "s/^iteration: .*/iteration: $new_iteration/" "$STATE_FILE" && rm -f "${STATE_FILE}.bak"

# Build the continuation message
system_msg="[Ralph Loop - Iteration $new_iteration"
if [[ "$max_iterations" -gt 0 ]]; then
    system_msg+=" of $max_iterations"
fi
system_msg+="]

You are in a Ralph loop. Your previous work is saved in files and git.
Read your previous output, assess progress, and continue working.

CRITICAL: Only output <promise>$completion_promise</promise> when the task is GENUINELY complete.
Do NOT lie to escape the loop. Continue working until done."

# Output JSON to block exit and re-inject prompt
cat << EOF
{
  "decision": "block",
  "reason": "Ralph loop iteration $new_iteration",
  "message": "$system_msg\n\n---\n\n$prompt"
}
EOF
