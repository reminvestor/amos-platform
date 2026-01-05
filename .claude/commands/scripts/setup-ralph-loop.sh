#!/bin/bash
# setup-ralph-loop.sh - Initialize Ralph Wiggum loop state
# Part of the Ralph Wiggum technique for iterative AI development

set -e

STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/ralph-loop.local.md"

usage() {
    cat << 'EOF'
Usage: setup-ralph-loop.sh "<PROMPT>" [OPTIONS]

Options:
  --max-iterations <n>       Stop after N iterations (default: infinite)
  --completion-promise <text> Phrase to output when done (wrapped in <promise> tags)
  -h, --help                 Show this help

Example:
  setup-ralph-loop.sh "Build a REST API with tests" --max-iterations 20 --completion-promise "COMPLETE"

How to exit the loop:
  - Output: <promise>YOUR_PHRASE</promise> (if --completion-promise was set)
  - Reach --max-iterations (if set)
  - Run /cancel-ralph

CRITICAL: Only output the completion promise when the task is GENUINELY complete.
Do NOT output false statements to escape the loop.
EOF
}

# Parse arguments
PROMPT=""
MAX_ITERATIONS=""
COMPLETION_PROMISE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-iterations)
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        --completion-promise)
            COMPLETION_PROMISE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$PROMPT" ]]; then
                PROMPT="$1"
            else
                PROMPT="$PROMPT $1"
            fi
            shift
            ;;
    esac
done

# Validate prompt
if [[ -z "$PROMPT" ]]; then
    echo "Error: PROMPT is required"
    usage
    exit 1
fi

# Validate max_iterations if provided
if [[ -n "$MAX_ITERATIONS" ]] && ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    echo "Error: --max-iterations must be a positive integer"
    exit 1
fi

# Create state file with YAML frontmatter
mkdir -p "$(dirname "$STATE_FILE")"

cat > "$STATE_FILE" << EOF
---
iteration: 1
max_iterations: ${MAX_ITERATIONS:-0}
completion_promise: "${COMPLETION_PROMISE}"
started_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
---

# Ralph Loop Prompt

${PROMPT}
EOF

# Output confirmation
echo "Ralph loop initialized!"
echo ""
echo "Configuration:"
echo "  - Iteration: 1"
if [[ -n "$MAX_ITERATIONS" ]]; then
    echo "  - Max iterations: $MAX_ITERATIONS"
else
    echo "  - Max iterations: unlimited (use /cancel-ralph to stop)"
fi
if [[ -n "$COMPLETION_PROMISE" ]]; then
    echo "  - Completion promise: <promise>$COMPLETION_PROMISE</promise>"
fi
echo ""
echo "Monitor progress: grep '^iteration:' .claude/ralph-loop.local.md"
echo "Cancel loop: /cancel-ralph"
echo ""
echo "Starting loop with prompt:"
echo "---"
echo "$PROMPT"
