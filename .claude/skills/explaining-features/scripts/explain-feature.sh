#!/bin/bash
set -e

# Explaining Features - Generate user-facing documentation
# Usage: explain-feature.sh [FEATURE] [AUDIENCE]
# Audiences: users, admins, developers

FEATURE="$1"
AUDIENCE="${2:-users}"

# Interactive selection if no feature provided
if [ -z "$FEATURE" ]; then
  echo "📖 Feature Documentation Generator"
  echo ""
  echo "Available features:"
  docker-compose run --rm web rails runner "
    ActiveRecord::Base.descendants
      .reject(&:abstract_class?)
      .map(&:name)
      .reject { |m| ['User', 'Entity', 'ApplicationRecord'].include?(m) }
      .sort
      .each_with_index { |f, i| puts \"  #{i+1}. #{f.pluralize.underscore}\" }
  " 2>/dev/null
  echo ""
  read -p "Enter feature name: " FEATURE
fi

echo "🔍 Analyzing feature: $FEATURE"
echo ""

# Analyze feature
docker-compose run --rm web rails runner "
  feature_name = '$FEATURE'.singularize.camelize

  begin
    model = feature_name.constantize
  rescue NameError
    puts '❌ Feature not found: $FEATURE'
    exit 1
  end

  puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
  puts \"Feature: #{feature_name}\"
  puts '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
  puts ''

  # Fields
  columns = model.columns.map(&:name).reject { |c| ['id', 'created_at', 'updated_at', 'entity_id'].include?(c) }
  puts 'Fields:'
  columns.each { |c| puts \"  - #{c}\" }
  puts ''

  # Associations
  associations = model.reflect_on_all_associations
  if associations.any?
    puts 'Related:'
    associations.each { |a| puts \"  - #{a.name} (#{a.macro})\" }
    puts ''
  end
" 2>/dev/null

# Generate documentation
mkdir -p docs/features

FEATURE_NAME=$(echo "$FEATURE" | sed 's/_/ /g' | sed 's/\b\(.\)/\u\1/g')
DOC_FILE="docs/features/$(echo $FEATURE | tr '[:upper:]' '[:lower:]')_${AUDIENCE}.md"

case "$AUDIENCE" in
  users)
    cat > "$DOC_FILE" <<EOF
# $FEATURE_NAME

## What is it?

$FEATURE_NAME allow you to [describe primary purpose].

## How to Use

### Creating a New $(echo $FEATURE | sed 's/s$//' | sed 's/_/ /g' | sed 's/\b\(.\)/\u\1/g')

1. Navigate to the $(echo $FEATURE | sed 's/_/ /g') section
2. Click "Create New"
3. Fill in the required information
4. Click "Save"

### Managing $FEATURE_NAME

**View All**: See a list of all your $(echo $FEATURE | sed 's/_/ /g')

**Edit**: Click the edit button to modify details

**Delete**: Remove $(echo $FEATURE | sed 's/_/ /g') you no longer need

## Best Practices

- Use descriptive names
- Keep information up to date
- Review regularly

---

*Auto-generated documentation - customize as needed*
EOF
    ;;

  admins)
    cat > "$DOC_FILE" <<EOF
# $FEATURE_NAME - Admin Guide

## Overview

Technical details about $(echo $FEATURE | sed 's/_/ /g') management.

## Features

### Creation
- Users can create new $(echo $FEATURE | sed 's/_/ /g')
- Scoped to entity for multi-tenancy
- Validates required fields

### Management
- CRUD operations via web interface
- Can be accessed via Scout AI tools
- Integration with workflow system

## Entity Scoping

All $(echo $FEATURE | sed 's/_/ /g') are scoped to entities. Users can only access $(echo $FEATURE | sed 's/_/ /g') belonging to their entity.

---

*Auto-generated documentation - customize as needed*
EOF
    ;;

  developers)
    docker-compose run --rm web rails runner "
      feature_name = '$FEATURE'.singularize.camelize
      model = feature_name.constantize

      puts \"# #{feature_name} - Developer Reference\"
      puts \"\"
      puts '## Model'
      puts \"\"
      puts '\`\`\`ruby'
      puts \"class #{feature_name} < ApplicationRecord\"
      model.reflect_on_all_associations.each { |a| puts \"  #{a.macro} :#{a.name}\" }
      puts 'end'
      puts '\`\`\`'
      puts \"\"
      puts '## Usage Examples'
      puts \"\"
      puts '\`\`\`ruby'
      puts \"#{feature_name}.create!(entity: current_entity, name: 'Example')\"
      puts \"#{feature_name}.for_entity(current_entity)\"
      puts '\`\`\`'
    " 2>/dev/null > "$DOC_FILE"
    ;;
esac

echo "✅ Documentation saved: $DOC_FILE"
echo ""
echo "Next steps:"
echo "  - Review and customize the documentation"
echo "  - Add screenshots if needed"
echo "  - Commit to repository"
