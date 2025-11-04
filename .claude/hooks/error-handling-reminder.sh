#!/bin/bash
# Error Handling Reminder Hook
# Runs after session ends to check for common Rails issues

# Skip if disabled
[[ -n "$SKIP_ERROR_REMINDER" ]] && exit 0

# Read from stdin
input=$(cat)

# Check for common patterns that might need error handling
if [[ "$input" =~ (rescue|exception|error|raise) ]]; then
  echo ""
  echo "✅ **Error Handling Tip**: Make sure exceptions are properly handled with:"
  echo "   - begin/rescue/ensure blocks"
  echo "   - Custom error classes inheriting from StandardError"
  echo "   - Proper error logging and user feedback"
fi

# Return input unchanged
echo "$input"
exit 0
