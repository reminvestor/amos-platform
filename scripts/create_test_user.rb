#!/usr/bin/env ruby
# Create test user with known password

puts "🔧 Creating Test User"
puts ""

# Find or create entity
entity = Entity.first

# Delete existing test user if exists
existing = User.find_by(email: 'test@example.com')
if existing
  existing.destroy
  puts "Removed existing test@example.com user"
end

# Create new user with known password
user = User.create!(
  email: 'test@example.com',
  password: 'password123',
  password_confirmation: 'password123',
  first_name: 'Test',
  last_name: 'User',
  entity: entity,
  onboarded: true,
  role: 'admin'
)

puts "✅ User created successfully!"
puts ""
puts "Login Credentials:"
puts "   URL:      http://localhost:3000"
puts "   Email:    test@example.com"
puts "   Password: password123"
puts "   Entity:   #{entity.name || entity.id}"
puts "   Role:     #{user.role}"
puts ""

# Verify it works
if user.valid_password?('password123')
  puts "✅ Password verification successful!"
else
  puts "❌ Password verification failed"
end

puts ""
puts "All users in database:"
User.all.each do |u|
  verified = u.valid_password?('password123') ? '✅' : '❌'
  puts "   #{verified} #{u.email} (#{u.role})"
end
