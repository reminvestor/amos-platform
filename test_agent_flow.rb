#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'

puts "🧪 Testing Agent Flow..."
puts "This will simulate creating a landing page and checking the flow"
puts ""
puts "Instructions:"
puts "1. Make sure your Rails app is running on port 5001"
puts "2. Open your browser to http://app.localhost:5001/scout"
puts "3. Type: 'can you help me create a landing page?'"
puts "4. Watch for:"
puts "   - Agent acknowledgment message"
puts "   - Task appearing in task monitor"
puts "   - Progress updates"
puts "   - Input prompt for headline"
puts ""
puts "Press Enter when ready to see expected flow..."
gets

puts "\n📋 Expected Flow:"
puts "1. You'll see: 'I'll help you create that landing page...'"
puts "2. Task monitor shows: 'landing_page_agent' task"
puts "3. Agent messages appear in chat"
puts "4. Progress bar updates (10%, 30%, etc.)"
puts "5. Prompt appears asking for headline"
puts "6. After you enter headline, more prompts follow"
puts ""
puts "✅ All messages should appear in the chat UI"
puts "✅ Task monitor should update in real-time"
puts "✅ No errors in browser console"
