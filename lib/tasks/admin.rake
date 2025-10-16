namespace :admin do
  desc "Create an admin user"
  task create_user: :environment do
    puts "Creating Admin User"
    puts "==================="

    print "Email: "
    email = STDIN.gets.chomp

    print "First Name: "
    first_name = STDIN.gets.chomp

    print "Last Name: "
    last_name = STDIN.gets.chomp

    print "Password: "
    password = STDIN.noecho(&:gets).chomp
    puts # New line after password

    print "Role (viewer/editor/super_admin) [super_admin]: "
    role = STDIN.gets.chomp
    role = "super_admin" if role.blank?

    begin
      admin = AdminUser.create!(
        email: email,
        first_name: first_name,
        last_name: last_name,
        password: password,
        role: role
      )

      puts "\n✅ Admin user created successfully!"
      puts "   Email: #{admin.email}"
      puts "   Name: #{admin.full_name}"
      puts "   Role: #{admin.role.humanize}"
      puts "\nYou can now login at: /admin/login"

    rescue => e
      puts "\n❌ Error creating admin user: #{e.message}"
      if admin && admin.errors.any?
        admin.errors.full_messages.each do |msg|
          puts "   - #{msg}"
        end
      end
    end
  end

  desc "List all admin users"
  task list_users: :environment do
    admins = AdminUser.all.order(:created_at)

    if admins.any?
      puts "\nAdmin Users (#{admins.count} total)"
      puts "=" * 80
      printf "%-30s %-20s %-15s %-10s %s\n", "Email", "Name", "Role", "Status", "Last Login"
      puts "-" * 80

      admins.each do |admin|
        status = admin.locked? ? "Locked" : "Active"
        last_login = admin.last_login_at ? admin.last_login_at.strftime("%Y-%m-%d %H:%M") : "Never"

        printf "%-30s %-20s %-15s %-10s %s\n",
               admin.email.truncate(30),
               admin.full_name.truncate(20),
               admin.role.humanize,
               status,
               last_login
      end
      puts
    else
      puts "\nNo admin users found."
      puts "Run 'rails admin:create_user' to create one."
    end
  end

  desc "Grant admin access to existing user"
  task grant_access: :environment do
    print "User email: "
    email = STDIN.gets.chomp

    user = User.find_by(email: email)
    unless user
      puts "❌ User not found with email: #{email}"
      return
    end

    if user.admin_user
      puts "⚠️  User already has admin access"
      puts "   Current role: #{user.admin_user.role.humanize}"
      return
    end

    print "Admin role (viewer/editor/super_admin) [editor]: "
    role = STDIN.gets.chomp
    role = "editor" if role.blank?

    admin = AdminUser.create!(
      email: user.email,
      first_name: user.first_name || "Admin",
      last_name: user.last_name || "User",
      password: SecureRandom.hex(16), # They'll use regular login
      role: role
    )

    # Link to user
    user.update!(admin_user: admin)

    puts "\n✅ Admin access granted!"
    puts "   User: #{user.email}"
    puts "   Role: #{admin.role.humanize}"
    puts "\nUser can now access admin portal with their regular login."
  end
end
