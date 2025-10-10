#!/usr/bin/env ruby
# test_anthropic_direct.rb - Direct test of Anthropic Messages API
# Run with: ruby test_anthropic_direct.rb

require 'rubygems'
require 'bundler/setup'
require 'dotenv/load'
require 'json'
require 'faraday'
require 'pp'

# Log API key (truncated for security)
key = ENV['ANTHROPIC_API_KEY'] || ''
if key.empty?
  puts "ERROR: No ANTHROPIC_API_KEY found in environment!"
  exit 1
end
puts "Using API key: #{key[0..5]}...#{key[-4..-1]}"

MODEL = "claude-3-7-sonnet-20250219"
API_URL = "https://api.anthropic.com/v1/messages"

begin
  puts "Creating Faraday connection..."
  conn = Faraday.new do |conn|
    conn.options.timeout = 120 # 2 minute timeout
  end
  
  puts "Preparing request to Claude 3.7 Messages API..."
  system_prompt = "You are a helpful AI assistant."
  user_message = "What's 2+2? Keep your answer very short."
  
  # Build the request body
  body = {
    model: MODEL,
    max_tokens: 150,
    temperature: 0.5,
    system: system_prompt,
    messages: [
      { role: "user", content: user_message }
    ]
  }
  
  start_time = Time.now
  puts "Sending request to Messages API..."
  
  response = conn.post do |req|
    req.url API_URL
    req.headers['Content-Type'] = 'application/json'
    req.headers['x-api-key'] = key
    req.headers['anthropic-version'] = '2023-06-01'
    req.body = body.to_json
  end
  
  elapsed = Time.now - start_time
  puts "Request completed in #{elapsed.round(2)} seconds with status: #{response.status}"
  
  # Parse the response
  json_response = JSON.parse(response.body)
  
  if response.status != 200
    puts "\nERROR from API:"
    pp json_response
  else
    puts "\nSUCCESS! Received response:"
    puts "-" * 50
    puts json_response.dig('content', 0, 'text')
    puts "-" * 50
    puts "Full response object:"
    pp json_response
  end
  
rescue => e
  puts "ERROR: #{e.class} - #{e.message}"
  puts e.backtrace[0..5]
end 