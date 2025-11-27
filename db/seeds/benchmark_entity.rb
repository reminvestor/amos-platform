# frozen_string_literal: true

# Create a dedicated entity and user for benchmark testing
# This isolates benchmark data from real customer data

puts "Creating benchmark test entity..."

benchmark_entity = Entity.find_or_create_by!(name: 'Benchmark Test Entity') do |entity|
  entity.slug = 'benchmark_test'
  entity.subdomain = 'benchmark-test'
  entity.settings = {
    'is_benchmark_entity' => true,
    'auto_cleanup' => true,
    'created_for' => 'automated_benchmarks'
  }
end

puts "  Entity: #{benchmark_entity.name} (ID: #{benchmark_entity.id})"

# Create benchmark user with admin role (for full access during benchmarks)
benchmark_user = User.find_or_create_by!(email: 'benchmark@amoslabs.internal') do |user|
  user.first_name = 'Benchmark'
  user.last_name = 'Runner'
  user.password = SecureRandom.hex(16) + 'Aa1!'  # Random password meeting requirements
  user.role = 'admin'  # Valid roles: admin, marketer, viewer
  user.entity = benchmark_entity
end

puts "  User: #{benchmark_user.email} (ID: #{benchmark_user.id})"

# Create entity membership if needed
if defined?(EntityMembership)
  EntityMembership.find_or_create_by!(user: benchmark_user, entity: benchmark_entity) do |membership|
    membership.role = 'owner'
  end
end

puts "✅ Benchmark test entity ready!"
puts "   Use Benchmarks::TestEnvironment.entity and .user to access"

