# Demo Users for Development
# This ensures demo users always exist with correct passwords

puts "🔧 Setting up demo users..."

# Create Demo Company entity
demo_entity = Entity.find_or_create_by!(name: 'Demo Company') do |entity|
  entity.subdomain = 'demo'
  entity.subscription_status = 'active'
  entity.trial_ends_at = 30.days.from_now
end

# Define demo users for each role
demo_users = [
  {
    email: 'admin@demo.com',
    first_name: 'Admin',
    last_name: 'User',
    role: 'admin'
  },
  {
    email: 'marketer@demo.com',
    first_name: 'Marketing',
    last_name: 'User',
    role: 'marketer'
  },
  {
    email: 'viewer@demo.com',
    first_name: 'Viewer',
    last_name: 'User',
    role: 'viewer'
  }
]

demo_users.each do |user_data|
  user = User.find_or_initialize_by(email: user_data[:email])
  user.assign_attributes(
    entity: demo_entity,
    first_name: user_data[:first_name],
    last_name: user_data[:last_name],
    password: 'password123',
    password_confirmation: 'password123',
    onboarded: true,
    role: user_data[:role]
  )

  if user.new_record?
    user.save!
    puts "✅ Created #{user_data[:email]} (#{user_data[:role]})"
  else
    # Always reset password to ensure it's correct
    user.save!
    puts "✅ Updated #{user_data[:email]} (#{user_data[:role]}, password reset)"
  end
  
  # Create EntityUser record with admin role for Team Space visibility
  entity_user = EntityUser.find_or_initialize_by(user: user, entity: demo_entity)
  entity_user.role = 'admin'
  entity_user.save!
  puts "   ↳ Added to Demo Company as admin"
end

# Seed AdminUser records for back-office access
puts "\n🔐 Setting up admin users for back-office access..."

admin_users = [
  {
    email: 'admin@demo.com',
    first_name: 'Admin',
    last_name: 'User',
    role: :super_admin
  }
]

admin_users.each do |admin_data|
  admin = AdminUser.find_or_initialize_by(email: admin_data[:email])
  admin.assign_attributes(
    first_name: admin_data[:first_name],
    last_name: admin_data[:last_name],
    password: 'password123',
    password_confirmation: 'password123',
    role: admin_data[:role]
  )

  if admin.new_record?
    admin.save!
    puts "✅ Created AdminUser: #{admin_data[:email]} (#{admin_data[:role]})"
  else
    admin.save!
    puts "✅ Updated AdminUser: #{admin_data[:email]} (#{admin_data[:role]})"
  end
end

puts "
📝 Demo Login Credentials:

   🎯 MAIN APPLICATION (app.localhost:3000):

   🔑 Admin User:
      Email: admin@demo.com
      Password: password123
      Role: Full access to all features

   📊 Marketer User:
      Email: marketer@demo.com
      Password: password123
      Role: Marketing features

   👁️  Viewer User:
      Email: viewer@demo.com
      Password: password123
      Role: Read-only access

   ⚙️ BACK-OFFICE ADMIN (localhost:3000/admin):

   🔐 Back-Office Access:
      Email: admin@demo.com
      Password: password123
      Role: super_admin
      Purpose: Platform administration and maintenance
"
