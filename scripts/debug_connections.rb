# Run this in Rails console to debug connection issues
# rails runner scripts/debug_connections.rb

puts "\n=== CONNECTIONS AUDIT ==="

# Find all Stripe connections
stripe_integration = Integration.find_by(slug: 'stripe')
if stripe_integration
  puts "\n📊 All Stripe connections in the system:"
  stripe_integration.connections.includes(:entity, :user).each do |conn|
    puts "  Connection ##{conn.id}:"
    puts "    - Entity: #{conn.entity&.name || 'NULL'} (ID: #{conn.entity_id || 'NULL'})"
    puts "    - User: #{conn.user&.email || 'NULL'} (ID: #{conn.user_id || 'NULL'})"
    puts "    - Status: #{conn.status}"
    puts "    - Created: #{conn.created_at}"
    puts "    - Has credentials: #{conn.integration_credentials.any?}"
    puts ""
  end
else
  puts "No Stripe integration found"
end

# Find connections with NULL user_id
puts "\n⚠️  Connections with NULL user_id:"
Connection.where(user_id: nil).includes(:integration, :entity).each do |conn|
  puts "  ##{conn.id}: #{conn.integration&.name} - Entity: #{conn.entity&.name || 'NULL'}"
end

# Find connections with NULL entity_id
puts "\n⚠️  Connections with NULL entity_id:"
Connection.where(entity_id: nil).includes(:integration, :user).each do |conn|
  puts "  ##{conn.id}: #{conn.integration&.name} - User: #{conn.user&.email || 'NULL'}"
end

# Check for duplicate connections (same integration, different entities/users)
puts "\n🔍 Check for potential cross-entity issues:"
Connection.select(:integration_id).group(:integration_id).having('COUNT(*) > 1').each do |result|
  integration = Integration.find_by(id: result.integration_id)
  next unless integration
  
  connections = Connection.where(integration_id: result.integration_id).includes(:entity, :user)
  puts "\n  #{integration.name} has #{connections.count} connections:"
  connections.each do |conn|
    puts "    ##{conn.id}: Entity=#{conn.entity&.name || 'NULL'} User=#{conn.user&.email || 'NULL'} Status=#{conn.status}"
  end
end

puts "\n=== END AUDIT ==="
