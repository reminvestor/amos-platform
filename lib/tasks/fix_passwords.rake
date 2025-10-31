namespace :dev do
  desc "Reset all user passwords to password123"
  task fix_passwords: :environment do
    puts '=== Resetting ALL User Passwords ==='
    puts

    User.find_each do |user|
      user.password = 'password123'
      user.password_confirmation = 'password123'
      user.onboarded = true
      user.save!(validate: false)

      # Verify immediately
      user.reload
      valid = user.valid_password?('password123')
      puts "✅ #{user.email.ljust(30)} - #{valid ? 'SUCCESS' : 'FAILED'}"
    end

    puts
    puts '✅ Password reset complete!'
    puts '📝 All users now have password: password123'
    puts
    puts '🌐 Login at: http://app.localhost:3000'
    puts '   Email: admin@demo.com (or any user email)'
    puts '   Password: password123'
  end
end
