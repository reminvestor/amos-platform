#!/usr/bin/env ruby
# Direct test of aggregation functionality

require_relative '../config/environment'

puts "\n=== DIRECT AGGREGATION TEST ==="

# Setup
user = User.first
entity = Entity.first

# Create test artifact
sample_data = [
  { 'plan' => 'premium', 'amount' => 99.99 },
  { 'plan' => 'basic', 'amount' => 29.99 },
  { 'plan' => 'premium', 'amount' => 99.99 }
]

artifact = Artifact.create!(
  entity: entity,
  user: user,
  name: 'Direct Test Data',
  source: 'test',
  schema: { 'plan' => 'string', 'amount' => 'float' },
  sample: sample_data,
  row_count: 3
)

puts "Created artifact ID: #{artifact.id}"

# Test 1: Direct service call
puts "\n1. Testing direct service call..."
service = ScoutGenericToolsService.new(user, entity)
result = service.execute_aggregate_artifact_data({
  'artifact_id' => artifact.id,
  'operation' => 'group_by_field',
  'field' => 'plan',
  'aggregations' => [
    { 'function' => 'count', 'field' => 'plan' },
    { 'function' => 'sum', 'field' => 'amount', 'alias' => 'total' }
  ]
})

if result[:success]
  puts "✅ Direct call successful!"
  result[:data][:results].each do |row|
      puts "   #{row['plan']}: #{row['count_plan']} customers, $#{row['total']}"
  end
else
  puts "❌ Direct call failed: #{result[:error]}"
end

# Test 2: Via execute_tool_by_name
puts "\n2. Testing via execute_tool_by_name..."
result2 = service.execute_tool_by_name('aggregate_artifact_data', {
  'artifact_id' => artifact.id,
  'operation' => 'simple_stats'
})

if result2[:success]
  puts "✅ Tool execution successful!"
  puts "   Stats: #{result2[:data][:results]}"
else
  puts "❌ Tool execution failed: #{result2[:error]}"
end

# Cleanup
artifact.destroy
puts "\n✅ Test complete and cleaned up"
