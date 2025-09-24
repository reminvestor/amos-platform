#!/usr/bin/env ruby
# Debug the ToolRunner flow

require_relative '../config/environment'

puts "\n=== DEBUGGING TOOL RUNNER FLOW ==="

# Setup
user = User.first
entity = Entity.first
puts "User: #{user.id} (#{user.email})"
puts "Entity: #{entity.id} (#{entity.name})"

# Create artifact
artifact = Artifact.create!(
  entity: entity,
  user: user,
  name: 'Debug Test',
  source: 'test',
  schema: { 'plan' => 'string' },
  sample: [{ 'plan' => 'test' }],
  row_count: 1
)
puts "\nCreated artifact ID: #{artifact.id}"
puts "Artifact entity: #{artifact.entity_id}"

# Test through ToolRunner
puts "\n1. Testing through ToolRunner..."
tool_runner = ToolRunner.new
result = tool_runner.call(
  tool: 'aggregate_artifact_data',
  inputs: {
    artifact_id: artifact.id,
    operation: 'simple_stats',
    user_id: user.id,
    entity_id: entity.id
  }
)

puts "Result status: #{result[:status]}"
puts "Result error: #{result[:error]}" if result[:error]

# Check what ScoutGenericToolsService sees
puts "\n2. Checking ScoutGenericToolsService directly..."
service = ScoutGenericToolsService.new(user, entity)
puts "Service @user: #{service.instance_variable_get(:@user)&.id}"
puts "Service @entity: #{service.instance_variable_get(:@entity)&.id}"

# Cleanup
artifact.destroy
puts "\n✅ Debug complete"
