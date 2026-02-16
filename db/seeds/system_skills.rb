# frozen_string_literal: true

# Seed SystemSkill records from SkillLibraryService constants
# These become the baseline that AMOS can evolve over time

puts "📚 Seeding system skills..."

# Integration skills
SkillLibraryService::INTEGRATION_SKILLS.each do |slug, data|
  skill = SystemSkill.find_or_initialize_by(slug: "integration_#{slug}")
  skill.assign_attributes(
    name: data[:name],
    skill_type: 'integration',
    content: data[:content],
    source: 'built-in',
    status: 'active',
    integration_name: slug,
    keywords: [slug]
  )

  if skill.new_record?
    skill.save!
    puts "  ✅ Created integration skill: #{data[:name]}"
  elsif skill.source == 'built-in' && skill.version == 1
    skill.save!
    puts "  🔄 Updated built-in skill: #{data[:name]}"
  else
    puts "  ⏭️  Skipped evolved skill: #{data[:name]} (v#{skill.version})"
  end
end

# Task skills
SkillLibraryService::TASK_SKILLS.each do |slug, data|
  skill = SystemSkill.find_or_initialize_by(slug: "task_#{slug}")
  skill.assign_attributes(
    name: data[:name],
    skill_type: 'task',
    content: data[:content],
    source: 'built-in',
    status: 'active',
    keywords: data[:keywords] || []
  )

  if skill.new_record?
    skill.save!
    puts "  ✅ Created task skill: #{data[:name]}"
  elsif skill.source == 'built-in' && skill.version == 1
    skill.save!
    puts "  🔄 Updated built-in skill: #{data[:name]}"
  else
    puts "  ⏭️  Skipped evolved skill: #{data[:name]} (v#{skill.version})"
  end
end

total = SystemSkill.count
puts "📚 System skills seeded: #{total} total"
