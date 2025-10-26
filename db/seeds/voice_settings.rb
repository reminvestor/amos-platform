# Voice Assistant Settings Seed Data
#
# Seeds default Deepgram configuration settings for the voice assistant.
# These settings control WebSocket parameters like timing, VAD, and audio processing.
#
# Run with: rails runner db/seeds/voice_settings.rb
# Or as part of: rails db:seed

puts "🔧 Seeding Voice Assistant default settings..."

VoiceAssistantSetting.seed_defaults!

puts "✅ Voice Assistant settings seeded successfully!"
puts "   Total settings: #{VoiceAssistantSetting.count}"

# Display seeded settings grouped by category
settings_by_category = VoiceAssistantSetting.all.group_by(&:category)
settings_by_category.each do |category, settings|
  puts "   #{category}: #{settings.count} setting#{'s' unless settings.count == 1}"
end
