# Development helper tasks
namespace :dev do
  desc "Reset demo user passwords to 'password123'"
  task reset_passwords: :environment do
    unless Rails.env.development?
      puts "❌ This task can only be run in development environment!"
      exit 1
    end

    puts "🔧 Resetting demo user passwords..."
    puts

    demo_users = [
      { email: 'admin@demo.com', role: 'admin' },
      { email: 'marketer@demo.com', role: 'marketer' },
      { email: 'viewer@demo.com', role: 'viewer' }
    ]

    demo_users.each do |user_data|
      user = User.find_by(email: user_data[:email])
      if user
        user.password = 'password123'
        user.password_confirmation = 'password123'
        user.save!
        puts "✅ Reset password for #{user.email} (#{user.role})"
      else
        puts "⚠️  User not found: #{user_data[:email]}"
      end
    end

    puts
    puts "✅ Password reset complete!"
    puts
    puts "📝 Login Credentials:"
    puts "   URL: http://localhost:3000"
    puts "   Password (all users): password123"
    puts
    demo_users.each do |user_data|
      user = User.find_by(email: user_data[:email])
      if user
        puts "   🔑 #{user.email} (#{user.role})"
      end
    end
    puts
  end

  desc "Show demo login credentials"
  task show_logins: :environment do
    puts
    puts "=" * 60
    puts "🔑 DEMO LOGIN CREDENTIALS"
    puts "=" * 60
    puts
    puts "URL: http://localhost:3000"
    puts "Password (all users): password123"
    puts
    puts "Users:"

    demo_users = User.where(email: ['admin@demo.com', 'marketer@demo.com', 'viewer@demo.com'])

    if demo_users.any?
      demo_users.each do |user|
        status = user.valid_password?('password123') ? '✅' : '❌'
        puts "  #{status} #{user.email.ljust(25)} (#{user.role})"
      end
    else
      puts "  ⚠️  No demo users found! Run: rails db:seed"
    end

    puts
    puts "=" * 60
    puts
  end

  desc "Full development reset (db:reset + seed)"
  task full_reset: :environment do
    unless Rails.env.development?
      puts "❌ This task can only be run in development environment!"
      exit 1
    end

    puts "🔄 Performing full development reset..."
    puts

    Rake::Task['db:reset'].invoke
    Rake::Task['db:seed'].invoke

    puts
    puts "✅ Full reset complete!"
    Rake::Task['dev:show_logins'].invoke
  end
end
