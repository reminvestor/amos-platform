#!/usr/bin/env ruby
# Script to find and fix incorrectly saved Scout messages

# Find all assistant messages that contain just "hello" or other simple greetings
suspicious_messages = ScoutMessage.where(role: 'assistant').where("content ILIKE ?", "%hello%").where("LENGTH(content) < 20")

puts "Found #{suspicious_messages.count} suspicious assistant messages"

suspicious_messages.each do |msg|
  puts "\nMessage ID: #{msg.id}"
  puts "Session: #{msg.session_id}"
  puts "Content: #{msg.content}"
  puts "Created: #{msg.created_at}"
  
  # Check if there's a user message with the same content in the same session around the same time
  potential_duplicate = ScoutMessage.where(
    session_id: msg.session_id,
    role: 'user',
    content: msg.content
  ).where("created_at BETWEEN ? AND ?", msg.created_at - 5.seconds, msg.created_at + 5.seconds).first
  
  if potential_duplicate
    puts "Found matching user message (ID: #{potential_duplicate.id}) - this assistant message is likely a duplicate"
    puts "Deleting incorrect assistant message..."
    msg.destroy
  else
    # Check if this looks like a greeting that shouldn't be from assistant
    if msg.content.strip.downcase.match?(/^(hello|hi|hey|yo|sup|greetings)[\s!?]*$/i)
      puts "This looks like a user greeting incorrectly saved as assistant"
      # Don't auto-delete, just flag it
      puts "Consider deleting this message manually"
    end
  end
end

puts "\nDone!"
