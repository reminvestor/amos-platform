#!/usr/bin/env ruby
# Quick test script for parallel processing
# Run with: rails runner scripts/test_parallel.rb

puts "\n🧪 Testing Parallel Processing Detection\n"

controller = ScoutController.new
controller.instance_variable_set(:@_request, ActionDispatch::Request.new({}))

test_messages = [
  "Pull my top 10 customers from Stripe and also give me an overview of contacts",
  "What time is it?",
  "Analyze campaigns and schedule meetings",
  "Show me X and Y",
  "Can you do this?",
  "First do A, then do B, and finally do C",
  "Compare sales data and create a report"
]

test_messages.each do |msg|
  # Use send to call private method
  is_parallel = controller.send(:should_use_parallel_processing?, msg, [])
  emoji = is_parallel ? "✅" : "❌"
  puts "#{emoji} #{msg[0..60]}... => #{is_parallel ? 'PARALLEL' : 'Sequential'}"
end

puts "\n📊 Testing with files:"
is_parallel = controller.send(:should_use_parallel_processing?, "Analyze these", ["file1.pdf", "file2.pdf"])
puts "✅ 2 files attached => #{is_parallel ? 'PARALLEL' : 'Sequential'}"

puts "\n✨ Done!"
