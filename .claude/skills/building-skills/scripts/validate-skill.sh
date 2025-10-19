#!/bin/bash
# Validate an Agent Skill has proper format

set -e

SKILL_DIR="$1"

if [ -z "$SKILL_DIR" ]; then
  echo "Usage: $0 <skill-directory>"
  echo ""
  echo "Available skills:"
  find .claude/skills -type d -name "*-skill" -maxdepth 1
  exit 1
fi

if [ ! -d "$SKILL_DIR" ]; then
  echo "❌ Directory not found: $SKILL_DIR"
  exit 1
fi

echo "🔍 Validating skill: $SKILL_DIR"
echo ""

ERRORS=0

# Check for SKILL.md
if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
  echo "❌ Missing SKILL.md file"
  ERRORS=$((ERRORS + 1))
else
  echo "✅ SKILL.md exists"

  # Check SKILL.md structure
  if ! grep -q "^# " "$SKILL_DIR/SKILL.md"; then
    echo "⚠️  SKILL.md should start with level 1 heading"
    ERRORS=$((ERRORS + 1))
  fi

  if ! grep -q "^## Description" "$SKILL_DIR/SKILL.md"; then
    echo "⚠️  SKILL.md should have ## Description section"
    ERRORS=$((ERRORS + 1))
  fi

  if ! grep -q "^## Instructions" "$SKILL_DIR/SKILL.md"; then
    echo "⚠️  SKILL.md should have ## Instructions section"
    ERRORS=$((ERRORS + 1))
  fi

  # Check length
  LINE_COUNT=$(wc -l < "$SKILL_DIR/SKILL.md")
  if [ "$LINE_COUNT" -gt 500 ]; then
    echo "⚠️  SKILL.md is $LINE_COUNT lines (recommend <500 lines)"
    ERRORS=$((ERRORS + 1))
  else
    echo "✅ SKILL.md length is good ($LINE_COUNT lines)"
  fi
fi

# Check directory structure
if [ -d "$SKILL_DIR/scripts" ]; then
  echo "✅ scripts/ directory exists"

  SCRIPT_COUNT=$(find "$SKILL_DIR/scripts" -name "*.sh" | wc -l)
  if [ "$SCRIPT_COUNT" -gt 0 ]; then
    echo "   Found $SCRIPT_COUNT script(s)"

    # Check if scripts are executable
    while IFS= read -r script; do
      if [ ! -x "$script" ]; then
        echo "⚠️  Script not executable: $script"
        ERRORS=$((ERRORS + 1))
      fi
    done < <(find "$SKILL_DIR/scripts" -name "*.sh")
  fi
fi

if [ -d "$SKILL_DIR/resources" ]; then
  echo "✅ resources/ directory exists"

  RESOURCE_COUNT=$(find "$SKILL_DIR/resources" -type f | wc -l)
  if [ "$RESOURCE_COUNT" -gt 0 ]; then
    echo "   Found $RESOURCE_COUNT resource file(s)"
  fi
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo "✅ Skill validation passed!"
  exit 0
else
  echo "❌ Found $ERRORS issue(s)"
  exit 1
fi
