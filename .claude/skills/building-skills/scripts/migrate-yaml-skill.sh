#!/bin/bash
# Migrate a YAML skill file to proper Agent Skills format

set -e

YAML_FILE="$1"

if [ -z "$YAML_FILE" ]; then
  echo "Usage: $0 <path-to-yaml-skill>"
  echo ""
  echo "Available YAML skills:"
  find .claude/skills -name "*.yaml" -type f
  exit 1
fi

if [ ! -f "$YAML_FILE" ]; then
  echo "❌ File not found: $YAML_FILE"
  exit 1
fi

# Extract skill name from YAML
SKILL_NAME=$(grep "^name:" "$YAML_FILE" | cut -d: -f2 | tr -d ' ')

if [ -z "$SKILL_NAME" ]; then
  echo "❌ Could not extract skill name from YAML file"
  exit 1
fi

# Convert to gerund form (this is a simple heuristic)
# In practice, Claude should help determine the proper gerund name
SKILL_DIR=".claude/skills/${SKILL_NAME}-skill"

echo "📦 Migrating $SKILL_NAME..."
echo "   Source: $YAML_FILE"
echo "   Target: $SKILL_DIR"
echo ""

# Create directory structure
mkdir -p "$SKILL_DIR"/{scripts,resources}

echo "✅ Created directory structure"
echo ""
echo "⚠️  Manual steps required:"
echo "   1. Create $SKILL_DIR/SKILL.md with proper format"
echo "   2. Extract bash code blocks to scripts/"
echo "   3. Create reference materials in resources/"
echo "   4. Make scripts executable: chmod +x $SKILL_DIR/scripts/*.sh"
echo "   5. Test the migrated skill"
echo ""
echo "💡 Use Claude Code to help with the migration!"
