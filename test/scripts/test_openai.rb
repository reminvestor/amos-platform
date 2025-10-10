#!/usr/bin/env ruby

# Quick test script for OpenAI GPT-5 integration
# Usage: OPENAI_API_KEY=your_key AI_PROVIDER=openai ruby test_openai.rb

require_relative 'config/environment'

puts "🤖 Testing OpenAI GPT-5 Integration"
puts "===================================="

# Check if API key is set
if ENV['OPENAI_API_KEY'].to_s.strip.empty?
  puts "❌ Please set OPENAI_API_KEY environment variable"
  puts "   Example: OPENAI_API_KEY=your_key AI_PROVIDER=openai ruby test_openai.rb"
  exit 1
end

begin
  # Test basic OpenAI service
  puts "1. Testing OpenaiService..."
  openai = OpenaiService.new
  response = openai.send_message("You are a helpful assistant.", "Reply with just the word OK.", model: 'gpt-5', max_tokens: 10)

  if response && response.strip.upcase.include?("OK")
    puts "✅ OpenAI connection successful!"
    puts "   Response: #{response.inspect}"
  else
    puts "❌ OpenAI connection returned unexpected response"
    puts "   Response: #{response.inspect}"
  end

  puts "\n2. Testing Scout with OpenAI (AI_PROVIDER=openai)..."
  user = User.first
  entity = Entity.first

  if user && entity
    puts "   Using User: #{user.email}"
    puts "   Using Entity: #{entity.name}"

    # Temporarily force provider at runtime if needed
    ENV['AI_PROVIDER'] ||= 'openai'

    scout = ScoutGenericToolsService.new(user, entity)
    scout_response = scout.process_message_with_tools("Hello! Just say hi back.", [])

    puts "✅ Scout with OpenAI working!"
    puts "   Response: #{scout_response[:message]}"
    puts "   Tools used: #{scout_response[:tools_used]}"
  else
    puts "❌ No user or entity found in database"
    puts "   Please ensure you have at least one user and entity"
  end

rescue => e
  puts "❌ Error: #{e.message}"
  puts "   #{e.class}: #{e.backtrace.first}"
end

puts "\n🎉 Test complete!"




