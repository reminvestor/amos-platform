#!/usr/bin/env ruby
# Reset all user passwords to 'password123'
#
# SECURITY: This script should NEVER run in production

if defined?(Rails) && Rails.env.production?
  puts "🚨 SECURITY ERROR: Cannot reset passwords in production!"
  puts "   This script is for development/testing only."
  exit 1
end

puts "🔧 Resetting All User Passwords"
puts ""

User.find_each do |user|
  user.update!(
    password: 'password123',
    password_confirmation: 'password123'
  )

  verified = user.valid_password?('password123') ? '✅' : '❌'
  puts "   #{verified} #{user.email.ljust(25)} → password123"
end

puts ""
puts "✅ All users now have password: password123"
puts ""
puts "Available accounts:"
puts "   • test@example.com    (admin)"
puts "   • user1@test.com      (admin)"
puts "   • user2@test.com      (marketer)"
puts "   • default@test.com    (admin)"
puts ""
puts "Login at: http://localhost:3000"
