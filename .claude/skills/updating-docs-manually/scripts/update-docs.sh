#!/usr/bin/env bash
# Update documentation based on code changes

set -e

SCOPE="${1:-ask}"
COMMIT="${2:-true}"

echo "📚 Documentation Update"
echo ""

# Determine what to update
if [ "$SCOPE" = "ask" ]; then
  echo "What documentation would you like to update?"
  echo ""
  echo "  a) Scout Tools documentation"
  echo "  b) Workflow Templates documentation"
  echo "  c) Models & Database schema"
  echo "  d) All documentation"
  echo ""
  read -p "Your choice (a/b/c/d): " choice

  case "$choice" in
    a) SCOPE="tools" ;;
    b) SCOPE="workflows" ;;
    c) SCOPE="models" ;;
    d) SCOPE="all" ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
fi

# Update Tools Documentation
if [ "$SCOPE" = "tools" ] || [ "$SCOPE" = "all" ]; then
  echo "🔧 Updating Scout Tools documentation..."
  echo ""

  # Generate tools list
  TOOLS_LIST=$(docker-compose run --rm web rails runner '
    require "tools/tool_catalog"

    catalog = Tools::ToolCatalog.instance
    tools = catalog.all_tools.sort_by { |name, _| name }

    tools.each do |name, tool_class|
      definition = tool_class.definition
      puts "### #{definition[:name]}"
      puts ""
      puts definition[:description]
      puts ""
      puts "**Parameters:**"

      if definition[:parameters][:properties]&.any?
        definition[:parameters][:properties].each do |param_name, param_def|
          required = definition[:parameters][:required]&.include?(param_name.to_s) ? "(required)" : "(optional)"
          puts "- `#{param_name}` #{required}: #{param_def[:description]}"
        end
      else
        puts "- None"
      end

      puts ""
      puts "**File:** `app/services/tools/#{name}.rb`"
      puts ""
      puts "---"
      puts ""
    end
  ' 2>/dev/null)

  # Create/update tools doc
  cat > docs/SCOUT_TOOLS.md <<EOF
# Scout AI Tools Reference

Auto-generated documentation for all available Scout AI tools.

**Last Updated:** $(date +"%Y-%m-%d %H:%M")

## Available Tools

$TOOLS_LIST

## Adding New Tools

1. Create file in \`app/services/tools/your_tool_tool.rb\`
2. Extend \`BaseTool\` class
3. Define \`self.definition\` method
4. Implement \`execute(args)\` method
5. ToolCatalog auto-discovers - no registration needed

See: \`docs/AGENT_ARCHITECTURE.md\` for details.
EOF

  echo "✅ Updated: docs/SCOUT_TOOLS.md"
  echo ""
fi

# Update Workflows Documentation
if [ "$SCOPE" = "workflows" ] || [ "$SCOPE" = "all" ]; then
  echo "🔄 Updating Workflow Templates documentation..."
  echo ""

  # Generate workflow list
  WORKFLOWS_LIST=""

  for template in app/workflow_templates/*_v2.yml; do
    if [ -f "$template" ]; then
      NAME=$(basename "$template" _v2.yml)
      TITLE=$(grep "^name:" "$template" | head -1 | sed 's/name: //' | tr -d '"')
      DESC=$(grep "^description:" "$template" | head -1 | sed 's/description: //' | tr -d '"')
      PHASES=$(grep "^  - name:" "$template" | sed 's/  - name: //' | tr '\n' ',' | sed 's/,$//')

      WORKFLOWS_LIST="${WORKFLOWS_LIST}
### $TITLE

**File:** \`$template\`

$DESC

**Phases:**
$(echo "$PHASES" | tr ',' '\n' | sed 's/^/- /')

**Keywords:**
$(grep -A5 "^keywords:" "$template" | grep "^  -" | sed 's/  - /- /' || echo "- N/A")

---

"
    fi
  done

  cat > docs/WORKFLOW_TEMPLATES.md <<EOF
# Workflow Templates Reference

Auto-generated documentation for V2 workflow templates.

**Last Updated:** $(date +"%Y-%m-%d %H:%M")

## Available Workflows

$WORKFLOWS_LIST

## Creating New Workflows

1. Create YAML file in \`app/workflow_templates/your_workflow_v2.yml\`
2. Set \`template_version: 2\`
3. Define three phases: \`gather_context\`, \`execute_goal\`, \`validate_result\`
4. Add keywords for planner matching
5. System auto-discovers - no registration needed

See: \`docs/V2_PURE_IMPLEMENTATION.md\` for details.
EOF

  echo "✅ Updated: docs/WORKFLOW_TEMPLATES.md"
  echo ""
fi

# Update Models Documentation
if [ "$SCOPE" = "models" ] || [ "$SCOPE" = "all" ]; then
  echo "📊 Updating Models & Database documentation..."
  echo ""

  # Generate models list
  MODELS_LIST=$(docker-compose run --rm web rails runner '
    ActiveRecord::Base.descendants.sort_by(&:name).each do |model|
      next if model.abstract_class?

      puts "### #{model.name}"
      puts ""
      puts "**Table:** `#{model.table_name}`"
      puts ""

      # Associations
      associations = []
      associations += model.reflect_on_all_associations(:belongs_to).map { |a| "belongs_to :#{a.name}" }
      associations += model.reflect_on_all_associations(:has_many).map { |a| "has_many :#{a.name}" }
      associations += model.reflect_on_all_associations(:has_one).map { |a| "has_one :#{a.name}" }

      if associations.any?
        puts "**Associations:**"
        associations.each { |a| puts "- #{a}" }
        puts ""
      end

      # Validations
      validators = model.validators.reject { |v| v.is_a?(ActiveRecord::Validations::PresenceValidator) && v.attributes.empty? }

      if validators.any?
        puts "**Validations:**"
        validators.each do |v|
          v.attributes.each do |attr|
            puts "- #{attr}: #{v.class.name.demodulize}"
          end
        end
        puts ""
      end

      puts "**File:** `app/models/#{model.name.underscore}.rb`"
      puts ""
      puts "---"
      puts ""
    end
  ' 2>/dev/null)

  cat > docs/MODELS_REFERENCE.md <<EOF
# Models Reference

Auto-generated documentation for Rails models.

**Last Updated:** $(date +"%Y-%m-%d %H:%M")

## Models

$MODELS_LIST

## Entity Scoping Pattern

All models in AMOS follow entity scoping for multi-tenancy:

\`\`\`ruby
class ModelName < ApplicationRecord
  belongs_to :entity

  validates :entity, presence: true
  scope :for_entity, ->(entity) { where(entity_id: entity.id) }
  scope :accessible_by, ->(user) { where(entity_id: user.entity_id) }
end
\`\`\`

See: \`CLAUDE.md\` for more details.
EOF

  echo "✅ Updated: docs/MODELS_REFERENCE.md"
  echo ""
fi

# Check for changes
echo "📝 Checking for documentation changes..."
echo ""

if git diff --quiet docs/; then
  echo "✅ No changes detected"
  echo "Documentation is already up to date."
  exit 0
fi

echo "Changes detected:"
git diff --stat docs/
echo ""

# Commit if requested
if [ "$COMMIT" = "true" ]; then
  echo "📝 Committing documentation updates..."
  echo ""

  git add docs/

  git commit -m "Update auto-generated documentation

Updates:
$(git diff --staged --name-only docs/ | sed 's/^/- /')

🤖 Generated with Claude Code"

  echo ""
  echo "✅ Documentation committed!"
  git log -1 --oneline
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Documentation Update Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
