#!/bin/bash
# Skill Activation Prompt for Rails/Agent Marketing Project
# Detects project context and suggests relevant skills

# Read the user prompt from stdin
input=$(cat)

# Detect Rails and project-specific context
context=""

if [[ -f "Gemfile" ]]; then
  context="Rails app"
  grep -q "devise" Gemfile 2>/dev/null && context="$context with Devise auth"
  grep -q "sidekiq\|activejob" Gemfile 2>/dev/null && context="$context and background jobs"
fi

if [[ -f "docker-compose.yml" ]]; then
  context="$context (containerized)"
fi

# Show context hint if detected
if [[ ! -z "$context" ]]; then
  echo ""
  echo "🔍 **Project Context Detected**: $context"
  echo "   Relevant skills: dark-theme-redesign, admin-redesign, documentation"
fi

# Return input unchanged
echo "$input"
