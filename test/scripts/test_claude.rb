#!/usr/bin/env ruby
# test_claude.rb - Test Claude 3.7 API Connection
# Run with: ruby test_claude.rb

require 'rubygems'
require 'bundler/setup'
require 'dotenv/load'
require 'json'
require 'pp'
require_relative 'app/services/claude_service'

# Log API key (truncated for security)
key = ENV['ANTHROPIC_API_KEY'] || ''
if key.empty?
  puts "ERROR: No ANTHROPIC_API_KEY found in environment!"
  exit 1
end
puts "Using API key: #{key[0..5]}...#{key[-4..-1]}"

begin
  puts "Creating Claude service..."
  claude = ClaudeService.new

  puts "Sending test message to Claude 3.7..."
  system_prompt = "You are a helpful AI assistant."
  user_message = "What's 2+2? Keep your answer very short."

  start_time = Time.now
  response = claude.send_message(system_prompt, user_message, max_tokens: 150)
  elapsed = Time.now - start_time

  puts "\nSUCCESS! Received response in #{elapsed.round(2)} seconds:"
  puts "-" * 50
  puts response
  puts "-" * 50

rescue => e
  puts "ERROR: #{e.class} - #{e.message}"
  puts e.backtrace[0..5]
end
