#!/usr/bin/env bash
# Test Scout AI tools interactively

set -e

TOOL_NAME="$1"
ENTITY_ID="$2"

echo "🔧 Scout AI Tool Testing"
echo ""

# List tools if none specified
if [ -z "$TOOL_NAME" ]; then
  echo "Available Scout AI Tools:"
  echo ""

  docker-compose run --rm web rails runner '
    require "tools/tool_catalog"

    catalog = Tools::ToolCatalog.instance
    tools = catalog.all_tools

    if tools.empty?
      puts "❌ No tools found"
      exit 1
    end

    tools.each do |name, tool_class|
      definition = tool_class.definition
      puts "  - #{name}"
      puts "    Description: #{definition[:description]}"
      puts ""
    end

    puts "Total tools: #{tools.size}"
  ' 2>/dev/null

  echo ""
  read -p "Which tool would you like to test? " TOOL_NAME
fi

# Load tool definition
echo "📖 Loading tool: $TOOL_NAME"
echo ""

docker-compose run --rm web rails runner '
  require "tools/tool_catalog"

  catalog = Tools::ToolCatalog.instance
  tool_class = catalog.get_tool("'$TOOL_NAME'")

  if tool_class.nil?
    puts "❌ Tool not found: '$TOOL_NAME'"
    exit 1
  end

  definition = tool_class.definition

  puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  puts "Tool: #{definition[:name]}"
  puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  puts ""
  puts "Description: #{definition[:description]}"
  puts ""
  puts "Parameters:"
  definition[:parameters][:properties]&.each do |param_name, param_def|
    required = definition[:parameters][:required]&.include?(param_name.to_s) ? "(required)" : "(optional)"
    puts "  - #{param_name} #{required}"
    puts "    Type: #{param_def[:type]}"
    puts "    Description: #{param_def[:description]}"
    puts ""
  end
  puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
' 2>/dev/null

# Setup test environment
echo ""
echo "🔧 Setting up test environment..."
echo ""

if [ -z "$ENTITY_ID" ]; then
  # Get first entity
  ENTITY_ID=$(docker-compose run --rm web rails runner "puts Entity.first&.id" 2>/dev/null | tail -1)

  if [ -z "$ENTITY_ID" ] || [ "$ENTITY_ID" = "nil" ]; then
    echo "❌ No entities found"
    exit 1
  fi
fi

# Get entity and user details
docker-compose run --rm web rails runner "
  entity = Entity.find($ENTITY_ID)
  user = entity.users.first

  if user.nil?
    puts '❌ No users found for entity'
    exit 1
  end

  puts \"Entity: #{entity.name} (ID: #{entity.id})\"
  puts \"User: #{user.email} (ID: #{user.id})\"
" 2>/dev/null

echo ""

# Choose test mode
echo "🧪 Test Modes:"
echo ""
echo "  a) Interactive mode (provide parameters)"
echo "  b) Example mode (use default/example parameters)"
echo "  c) View source code"
echo "  d) Show tool JSON definition"
echo ""
read -p "Your choice (a/b/c/d): " TEST_MODE

case "$TEST_MODE" in
  a)
    echo ""
    echo "📝 Enter tool parameters as JSON:"
    echo ""
    echo 'Example: {"name": "Test Campaign", "subject": "Hello"}'
    echo ""
    read -p "JSON parameters: " PARAMS

    echo ""
    echo "🚀 Executing tool: $TOOL_NAME"
    echo "   Parameters: $PARAMS"
    echo ""

    docker-compose run --rm web rails runner '
      require "tools/tool_catalog"
      require "json"

      entity = Entity.find('$ENTITY_ID')
      user = entity.users.first

      # Create workflow execution for context
      execution = WorkflowExecution.create!(
        entity: entity,
        user: user,
        template_name: "test",
        status: "in_progress"
      )

      catalog = Tools::ToolCatalog.instance
      tool_class = catalog.get_tool("'$TOOL_NAME'")

      tool = tool_class.new(user: user, entity: entity, workflow_execution: execution)

      params = JSON.parse('\''$PARAMS'\'')

      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "Executing tool..."
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts ""

      result = tool.execute(params)

      puts "Result:"
      puts JSON.pretty_generate(result)
      puts ""

      if result[:success]
        puts "✅ Tool executed successfully!"
      else
        puts "❌ Tool execution failed"
      end
    ' 2>/dev/null
    ;;

  b)
    echo ""
    echo "🚀 Executing tool with example parameters..."
    echo ""

    docker-compose run --rm web rails runner '
      require "tools/tool_catalog"

      entity = Entity.find('$ENTITY_ID')
      user = entity.users.first

      execution = WorkflowExecution.create!(
        entity: entity,
        user: user,
        template_name: "test",
        status: "in_progress"
      )

      catalog = Tools::ToolCatalog.instance
      tool_class = catalog.get_tool("'$TOOL_NAME'")
      tool = tool_class.new(user: user, entity: entity, workflow_execution: execution)

      # Generate example params based on definition
      definition = tool_class.definition
      params = {}

      definition[:parameters][:properties]&.each do |name, prop|
        case prop[:type]
        when "string"
          params[name] = "Test Value"
        when "integer"
          params[name] = 1
        when "boolean"
          params[name] = true
        when "array"
          params[name] = []
        when "object"
          params[name] = {}
        end
      end

      puts "Example Parameters:"
      puts JSON.pretty_generate(params)
      puts ""
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "Executing tool..."
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts ""

      begin
        result = tool.execute(params)

        puts "Result:"
        puts JSON.pretty_generate(result)
        puts ""

        if result[:success]
          puts "✅ Tool executed successfully!"
        else
          puts "❌ Tool execution failed"
        end
      rescue => e
        puts "❌ Error: #{e.message}"
        puts e.backtrace.first(3)
      end
    ' 2>/dev/null
    ;;

  c)
    echo ""
    echo "📄 Tool source code:"
    echo ""

    # Find tool file
    TOOL_FILE=$(find app/services/tools -name "*${TOOL_NAME}*.rb" -type f | head -1)

    if [ -z "$TOOL_FILE" ]; then
      echo "❌ Tool file not found for: $TOOL_NAME"
      exit 1
    fi

    echo "File: $TOOL_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "$TOOL_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ;;

  d)
    echo ""
    echo "📋 Tool JSON definition (for Bedrock):"
    echo ""

    docker-compose run --rm web rails runner '
      require "tools/tool_catalog"

      catalog = Tools::ToolCatalog.instance
      tool_class = catalog.get_tool("'$TOOL_NAME'")
      definition = tool_class.definition

      puts JSON.pretty_generate(definition)
    ' 2>/dev/null
    ;;

  *)
    echo "Invalid choice"
    exit 1
    ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Tool test complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
