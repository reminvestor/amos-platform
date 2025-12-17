# AI Rulesets System Presets Seed Data
#
# Seeds default system presets that provide baseline behavioral constraints for Scout AI.
# These are global rules that apply to all entities and cannot be deleted.
#
# Run with: rails runner db/seeds/ai_rulesets.rb
# Or as part of: rails db:seed

puts "🔧 Seeding AI Ruleset system presets..."

# System Presets - These are protected and cannot be deleted
system_presets = [
  {
    name: "Core Safety Rules",
    description: "Essential security and data protection rules that apply to all AI interactions",
    category: "safety",
    priority: 100,
    is_system: true,
    is_active: true,
    rules: [
      "Never reveal API keys, passwords, secrets, or internal credentials in responses",
      "Only access data belonging to the current user's entity - never cross entity boundaries",
      "Warn user before operations that affect more than 100 records",
      "Do not execute delete operations on critical data without explicit user confirmation",
      "Never expose internal system paths, database schemas, or infrastructure details"
    ]
  },
  {
    name: "Professional Communication",
    description: "Communication style guidelines for professional, helpful AI interactions",
    category: "tone",
    priority: 90,
    is_system: true,
    is_active: true,
    rules: [
      "Use clear, professional language appropriate for business communication",
      "Be concise but thorough - avoid unnecessary verbosity",
      "Acknowledge errors gracefully and offer corrective solutions",
      "Maintain a helpful, solution-oriented tone in all responses",
      "Use proper grammar and avoid slang unless matching brand voice"
    ]
  },
  {
    name: "Email Compliance",
    description: "Compliance rules for email marketing activities",
    category: "compliance",
    priority: 80,
    is_system: true,
    is_active: true,
    rules: [
      "Always remind users that emails must include unsubscribe links",
      "Suggest checking spam score before sending campaigns",
      "Recommend sender reputation verification for new domains",
      "Warn about sending volume limits and warm-up periods for new senders",
      "Advise on CAN-SPAM and GDPR requirements when relevant"
    ]
  },
  {
    name: "Marketing Best Practices",
    description: "Industry best practices for marketing automation and campaigns",
    category: "domain",
    priority: 70,
    is_system: true,
    is_active: true,
    rules: [
      "Suggest A/B testing for significant campaign changes",
      "Recommend segmentation strategies for better targeting",
      "Advise on optimal send times based on audience data",
      "Consider brand voice and consistency in content suggestions",
      "Prioritize engagement metrics over vanity metrics"
    ]
  },
  {
    name: "Resource Protection",
    description: "Rules to prevent resource abuse and protect system stability",
    category: "safety",
    priority: 85,
    is_system: true,
    is_active: true,
    rules: [
      "Suggest batching for bulk operations exceeding 500 items",
      "Recommend scheduling large operations during off-peak hours",
      "Alert if an operation might significantly impact system resources",
      "Avoid infinite loops or recursive operations without clear termination",
      "Limit concurrent API calls to external services"
    ]
  }
]

created_count = 0
updated_count = 0

system_presets.each do |preset|
  existing = AiRuleset.find_by(name: preset[:name], is_system: true)

  if existing
    # Update existing system preset rules (keep them current)
    if existing.update(rules: preset[:rules], description: preset[:description], priority: preset[:priority])
      updated_count += 1
      puts "   Updated: #{preset[:name]}"
    end
  else
    # Create new system preset
    ruleset = AiRuleset.new(preset)
    if ruleset.save
      created_count += 1
      puts "   Created: #{preset[:name]}"
    else
      puts "   ⚠️  Failed to create #{preset[:name]}: #{ruleset.errors.full_messages.join(', ')}"
    end
  end
end

puts "✅ AI Ruleset system presets seeded successfully!"
puts "   Created: #{created_count}"
puts "   Updated: #{updated_count}"
puts "   Total system presets: #{AiRuleset.system_presets.count}"
puts "   Total active rulesets: #{AiRuleset.active.count}"

# Display summary by category
puts "\n   By Category:"
AiRuleset::CATEGORIES.each do |category|
  count = AiRuleset.by_category(category).count
  puts "   - #{category.titleize}: #{count}" if count > 0
end
