#!/usr/bin/env ruby

# Quick test script for Grok integration
# Usage: XAI_API_KEY=your_key ruby test_grok.rb

require_relative 'config/environment'

puts "🤖 Testing Grok 4 Integration"
puts "================================"

# Check if API key is set
if ENV['XAI_API_KEY'].blank?
  puts "❌ Please set XAI_API_KEY environment variable"
  puts "   Example: XAI_API_KEY=your_key ruby test_grok.rb"
  exit 1
end

begin
  # Test basic Grok service
  puts "1. Testing GrokService..."
  grok = GrokService.new
  response = grok.test_connection

  if response
    puts "✅ Grok connection successful!"
    puts "   Response: #{response}"
  else
    puts "❌ Grok connection failed"
    exit 1
  end

  puts "\n2. Testing Scout with Grok..."

  # Create test user and entity (using first available)
  user = User.first
  entity = Entity.first

  if user && entity
    puts "   Using User: #{user.email}"
    puts "   Using Entity: #{entity.name}"

    # Test Scout service
    scout = ScoutGenericToolsService.new(user, entity)
    scout_response = scout.process_message_with_tools("Hello! Just say hi back.", [])

    puts "✅ Scout with Grok working!"
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
