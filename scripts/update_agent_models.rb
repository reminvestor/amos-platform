# Run with: podman compose exec web rails runner scripts/update_agent_models.rb
#
# Clears ai_model from all agents so they inherit from the system default.
# This enables:
#   1. Auto-mode routing via SmartRouter (pick model based on task type)
#   2. System-level model updates without touching each agent
#   3. Future flexibility for multi-model routing (Qwen3-Next-80B for reasoning,
#      Qwen3-VL-235B for vision, DeepSeek-R1 for deep thinking, etc.)

puts "=" * 80
puts "🔄 CLEARING AGENT MODEL OVERRIDES (inherit from system)"
puts "=" * 80

puts "\n📋 Agents with model overrides (before):"
agents_with_models = AgentPlugin.where.not(ai_model: [nil, '']).order(:name)
agents_with_models.each do |a|
  puts "  - #{a.slug}: #{a.ai_model}"
end

if agents_with_models.empty?
  puts "  (none - all agents already inherit from system)"
  exit 0
end

# Clear all model overrides - agents will inherit from system default
updated_count = 0
agents_with_models.find_each do |agent|
  old_model = agent.ai_model
  agent.update!(ai_model: nil)
  puts "  ✅ #{agent.slug}: #{old_model} → (system default)"
  updated_count += 1
end

puts "\n📋 Agents with model overrides (after):"
remaining = AgentPlugin.where.not(ai_model: [nil, '']).order(:name)
if remaining.any?
  remaining.each { |a| puts "  - #{a.slug}: #{a.ai_model}" }
else
  puts "  (none - all agents now inherit from system)"
end

puts "\n" + "=" * 80
puts "✅ Cleared model override from #{updated_count} agents"
puts ""
puts "📝 Agents will now use the system default model."
puts "   To change the default, update BedrockService or SmartRouterService."
puts ""
puts "🧠 Model routing options:"
puts "   - Qwen3-Next-80B: Fast reasoning, coding (65k context)"
puts "   - Qwen3-VL-235B: Vision/multimodal, heavy tasks (256k context)"
puts "   - DeepSeek-R1: Deep thinking, complex reasoning"
puts "=" * 80
