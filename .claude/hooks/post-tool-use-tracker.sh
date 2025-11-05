#!/bin/bash
# Post-tool-use tracker for Rails projects
# Logs file changes and notes for debugging

# Read tool information from stdin (JSON format)
input=$(cat)

# Log to a simple tracker file
log_file="$CLAUDE_PROJECT_DIR/.claude/.hook-logs"
mkdir -p "$(dirname "$log_file")"

# Log timestamp and input summary
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$timestamp] Tool executed:" >> "$log_file"
echo "$input" | head -5 >> "$log_file"
echo "---" >> "$log_file"

# Keep log file size manageable (last 100 entries)
if [[ -f "$log_file" ]]; then
  tail -100 "$log_file" > "$log_file.tmp"
  mv "$log_file.tmp" "$log_file"
fi

# Return input unchanged
echo "$input"
exit 0