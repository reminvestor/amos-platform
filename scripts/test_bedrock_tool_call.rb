# Run with: docker-compose exec web rails runner scripts/test_bedrock_tool_call.rb
#
# This script directly tests if the Bedrock model calls tools when given them.
# Bypasses the agent framework to isolate the issue.

puts "=" * 80
puts "🧪 TESTING BEDROCK TOOL CALLING DIRECTLY"
puts "=" * 80

user = User.first
entity = Entity.first

unless user && entity
  puts "❌ Missing user or entity"
  exit 1
end

# Find a landing page
landing_page = LandingPage.where(entity_id: entity.id).first
unless landing_page
  puts "❌ No landing page found"
  exit 1
end

puts "\n📋 Configuration:"
puts "   User: #{user.email}"
puts "   Entity: #{entity.name}"
puts "   Landing Page: #{landing_page.title} (ID: #{landing_page.id})"

# Create a simple tool definition
tools = [
  {
    name: "edit_landing_page_section",
    description: "Edit a specific section of a landing page. Use this to make changes like moving elements, updating content, etc.",
    input_schema: {
      type: "object",
      properties: {
        landing_page_id: { type: "integer", description: "ID of the landing page to edit" },
        section: { type: "string", description: "Which section to edit: hero, header, features, etc." },
        action: { type: "string", description: "Action: replace, update, add, remove" },
        instruction: { type: "string", description: "What to change" }
      },
      required: ["landing_page_id", "section", "action"]
    }
  }
]

system_prompt = <<~PROMPT
You are a landing page editor. Your ONLY job is to call tools to make changes.

⛔ MANDATORY RULE: You MUST call a tool to make any changes.
❌ NEVER respond with text claiming you made changes without calling a tool.
❌ If you say "I've repositioned your video!" without calling a tool, you are LYING.

✅ ALWAYS call the edit_landing_page_section tool to make changes.
✅ Wait for the tool result before confirming success.
PROMPT

messages = [
  { 
    role: "user", 
    content: "Please move the video below the hero text on landing page ID #{landing_page.id}"
  }
]

puts "\n📝 System Prompt:"
puts system_prompt
puts "\n📝 User Message:"
puts messages.first[:content]
puts "\n🔧 Tools Provided:"
tools.each { |t| puts "   - #{t[:name]}: #{t[:description].truncate(80)}" }

# Create bedrock service
bedrock = BedrockService.new(
  entity: entity,
  user: user,
  custom_model_id: 'qwen3-next-80b'
)

puts "\n" + "=" * 80
puts "🚀 CALLING BEDROCK (with tools)"
puts "=" * 80

begin
  start_time = Time.now
  
  # Call send_message_converse which handles tools
  response = bedrock.send_message_converse(
    system_prompt,
    messages,
    model: 'qwen3-next-80b',
    max_tokens: 2000,
    temperature: 0.7,
    tools: tools
  )
  
  duration = Time.now - start_time
  
  puts "\n✅ Completed in #{duration.round(2)}s"
  puts "\n📤 Response:"
  puts response.to_s.truncate(2000)
  
  puts "\n🔧 Tools Called:"
  tools_called = bedrock.tools_called || []
  if tools_called.any?
    tools_called.each { |t| puts "   ✅ #{t}" }
  else
    puts "   ❌ NO TOOLS WERE CALLED!"
    puts "   ⚠️  This means the model is hallucinating!"
  end
  
  # Check for hallucination patterns
  response_text = response.to_s.downcase
  hallucination_patterns = [
    /i['']ve (repositioned|updated|changed|moved)/,
    /✅.*i['']ve/,
    /made the edit/,
    /the video is now/
  ]
  
  if hallucination_patterns.any? { |p| response_text =~ p } && tools_called.empty?
    puts "\n" + "=" * 80
    puts "🎭 HALLUCINATION CONFIRMED!"
    puts "=" * 80
    puts "The model claimed to make changes but did NOT call any tools."
    puts "This is the bug we need to fix."
  end
  
rescue => e
  puts "\n❌ Error: #{e.class.name}"
  puts "   #{e.message}"
  e.backtrace.first(10).each { |line| puts "   #{line}" }
end

puts "\n" + "=" * 80
puts "🏁 TEST COMPLETE"
puts "=" * 80
