# Run with: docker-compose exec web rails runner scripts/test_agent_tool_call.rb
#
# This script tests whether the Landing Page Manager agent actually calls tools
# when asked to make edits.

puts "=" * 80
puts "🧪 TESTING AGENT TOOL CALLING BEHAVIOR"
puts "=" * 80

# Find test user and entity
user = User.first
entity = Entity.first
agent = AgentPlugin.find_by(slug: 'landing_page_manager')

unless user && entity && agent
  puts "❌ Missing required records:"
  puts "   User: #{user ? '✅' : '❌'}"
  puts "   Entity: #{entity ? '✅' : '❌'}"
  puts "   Agent: #{agent ? '✅' : '❌'}"
  exit 1
end

puts "\n📋 Test Configuration:"
puts "   User: #{user.email}"
puts "   Entity: #{entity.name}"
puts "   Agent: #{agent.name} (#{agent.slug})"

# Find a landing page to test with
landing_page = LandingPage.where(entity_id: entity.id).first
unless landing_page
  puts "❌ No landing page found for testing"
  exit 1
end

puts "   Landing Page: #{landing_page.title} (ID: #{landing_page.id})"

# Check what tools the agent has
puts "\n🔧 Agent Tools (#{agent.agent_tools.count} assigned):"
agent.agent_tools.each do |tool|
  puts "   - #{tool.tool_name}#{tool.required ? ' (required)' : ''}"
end

# Check if edit_landing_page_section tool exists in catalog
catalog = Tools::ToolCatalog.instance
edit_tool = catalog.get_tool_definition('edit_landing_page_section')
puts "\n🔍 edit_landing_page_section tool in catalog: #{edit_tool ? '✅' : '❌'}"
if edit_tool
  puts "   Name: #{edit_tool[:name]}"
  puts "   Description: #{edit_tool[:description].truncate(100)}"
end

# Test prompt
test_prompt = "Please move the video below the hero text on my '#{landing_page.title}' landing page"

puts "\n" + "=" * 80
puts "🚀 RUNNING AGENT EXECUTION"
puts "=" * 80
puts "\n📝 Test Prompt:"
puts "   #{test_prompt}"

# Create execution context
context = {
  entity: entity,
  user: user,
  agent_plugin: agent,
  session_id: SecureRandom.uuid
}

# Create the executor
executor = Agents::StandardPluginExecutor.new(
  prompt: test_prompt,
  role: agent.role,
  system_prompt: agent.system_prompt&.dig('prompt'),
  config: agent.configuration || {},
  capabilities: agent.agent_capabilities.pluck(:capability_name),
  context: context
)

puts "\n⏳ Executing agent (this may take a moment)..."

begin
  start_time = Time.now
  result = executor.run
  duration = Time.now - start_time
  
  puts "\n✅ Execution completed in #{duration.round(2)}s"
  puts "\n" + "=" * 80
  puts "📤 RESULT"
  puts "=" * 80
  
  if result.is_a?(Hash)
    puts "\n📊 Result Structure:"
    result.each do |key, value|
      value_preview = value.to_s.truncate(500)
      puts "   #{key}: #{value_preview}"
    end
    
    # Check for tool calls
    content = result[:content] || result['content']
    if content.is_a?(String)
      puts "\n📝 Response Content:"
      puts content.truncate(2000)
      
      # Check for hallucination patterns
      hallucination_patterns = [
        /i['']ve (repositioned|updated|changed|moved)/i,
        /✅.*i['']ve/i,
        /made the edit/i,
        /the video is now/i
      ]
      
      detected = hallucination_patterns.any? { |p| content =~ p }
      if detected
        puts "\n⚠️  HALLUCINATION PATTERN DETECTED!"
        puts "   The response claims to have made changes."
        puts "   Check if any tools were actually called above."
      end
    end
  else
    puts "\n📝 Raw Result:"
    puts result.to_s.truncate(2000)
  end
  
rescue => e
  puts "\n❌ Execution failed: #{e.class.name}"
  puts "   #{e.message}"
  puts "\n📚 Backtrace (first 10 lines):"
  e.backtrace.first(10).each { |line| puts "   #{line}" }
end

puts "\n" + "=" * 80
puts "🏁 TEST COMPLETE"
puts "=" * 80
