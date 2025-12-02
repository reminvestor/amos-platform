# frozen_string_literal: true

require_relative '../security_auditor'

namespace :security do
  desc "Run comprehensive security audit"
  task audit: :environment do |_task, args|
    puts "🔒 AMOS Security Audit"
    puts ""

    # Parse arguments
    category = ENV['CATEGORY'] # entity-isolation, admin-protection, role-checks, api-security, auth-bypass
    verbose = ENV['VERBOSE'] == 'true'
    report_file = ENV['REPORT']

    # Initialize auditor
    auditor = SecurityAuditor.new(verbose: verbose)

    # Run audit
    results = if category
                puts "Running #{category} audit...\n"
                auditor.run_category_audit(category)
              else
                auditor.run_full_audit
              end

    # Print report to console
    auditor.print_report(results)

    # Save to file if requested
    if report_file
      File.open(report_file, 'w') do |f|
        f.puts "AMOS Security Audit Report"
        f.puts "Generated: #{Time.now.utc}"
        f.puts ""
        f.puts "Total Issues: #{results[:summary][:total]}"
        f.puts "  Critical: #{results[:summary][:critical]}"
        f.puts "  High: #{results[:summary][:high]}"
        f.puts "  Medium: #{results[:summary][:medium]}"
        f.puts "  Low: #{results[:summary][:low]}"
        f.puts ""
        f.puts "=" * 60
        f.puts ""

        results[:issues].each do |issue|
          f.puts "[#{issue[:severity]}] #{issue[:title]}"
          f.puts "  Location: #{issue[:location]}" if issue[:location]
          f.puts "  Risk: #{issue[:risk]}"
          f.puts "  Fix: #{issue[:fix]}"
          f.puts "  Impact: #{issue[:impact]}" if issue[:impact]
          f.puts ""
        end
      end

      puts "\n📄 Report saved to: #{report_file}"
    end

    # Exit with error code if critical issues found
    critical_count = results[:summary][:critical]
    if critical_count > 0
      puts "\n⚠️  Exiting with error code due to #{critical_count} critical issue(s)"
      exit 1
    end
  end

  desc "Check entity isolation (multi-tenant security)"
  task entity_isolation: :environment do
    ENV['CATEGORY'] = 'entity-isolation'
    Rake::Task['security:audit'].invoke
  end

  desc "Check admin area protection"
  task admin_protection: :environment do
    ENV['CATEGORY'] = 'admin-protection'
    Rake::Task['security:audit'].invoke
  end

  desc "Check role-based access control"
  task role_checks: :environment do
    ENV['CATEGORY'] = 'role-checks'
    Rake::Task['security:audit'].invoke
  end

  desc "Check API security"
  task api_security: :environment do
    ENV['CATEGORY'] = 'api-security'
    Rake::Task['security:audit'].invoke
  end

  desc "Check authentication bypass vulnerabilities"
  task auth_bypass: :environment do
    ENV['CATEGORY'] = 'auth-bypass'
    Rake::Task['security:audit'].invoke
  end

  desc "Generate security report and save to file"
  task :report, [:filename] => :environment do |_task, args|
    filename = args[:filename] || "security_report_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt"
    ENV['REPORT'] = filename
    Rake::Task['security:audit'].invoke
  end

  desc "Run security audit with verbose output"
  task verbose: :environment do
    ENV['VERBOSE'] = 'true'
    Rake::Task['security:audit'].invoke
  end

  desc "Fix known security issues (interactive)"
  task fix: :environment do
    puts "🔧 Security Issue Auto-Fix"
    puts "=" * 60
    puts ""
    puts "This task will help you fix common security issues."
    puts ""

    # Run audit first
    auditor = SecurityAuditor.new(verbose: false)
    results = auditor.run_full_audit

    critical = results[:issues].select { |i| i[:severity] == SecurityAuditor::SEVERITY_CRITICAL }

    if critical.empty?
      puts "✅ No critical security issues found!"
      return
    end

    puts "Found #{critical.size} critical issue(s):"
    puts ""

    critical.each_with_index do |issue, idx|
      puts "#{idx + 1}. #{issue[:title]}"
      puts "   Risk: #{issue[:risk]}"
      puts "   Fix: #{issue[:fix]}"
      puts ""
    end

    puts "Would you like to see detailed fix instructions? (y/n)"
    response = STDIN.gets.chomp.downcase

    if response == 'y'
      puts ""
      puts "DETAILED FIX INSTRUCTIONS"
      puts "=" * 60
      puts ""

      critical.each do |issue|
        puts "Issue: #{issue[:title]}"
        puts "Location: #{issue[:location]}" if issue[:location]
        puts ""
        puts "Fix Instructions:"
        puts issue[:fix]
        puts ""
        puts "-" * 60
        puts ""
      end
    end

    puts "\n📚 For more information, see: docs/SECURITY_GUIDE.md"
  end

  desc "Show security audit statistics"
  task stats: :environment do
    puts "📊 AMOS Security Statistics"
    puts "=" * 60
    puts ""

    # Count files
    controllers = Dir.glob(Rails.root.join('app', 'controllers', '**', '*_controller.rb')).size
    models = Dir.glob(Rails.root.join('app', 'models', '*.rb')).size
    admin_controllers = Dir.glob(Rails.root.join('app', 'controllers', 'admin', '*_controller.rb')).size

    puts "Codebase:"
    puts "  Total Controllers: #{controllers}"
    puts "  Admin Controllers: #{admin_controllers}"
    puts "  Total Models: #{models}"
    puts ""

    # Count users and roles
    if defined?(User)
      total_users = User.count
      admin_users = User.where(role: :admin).count rescue 0
      viewer_users = User.where(role: :viewer).count rescue 0

      puts "Users:"
      puts "  Total Users: #{total_users}"
      puts "  Admin Users: #{admin_users}"
      puts "  Viewer Users: #{viewer_users}"
      puts ""
    end

    # Count entities
    if defined?(Entity)
      total_entities = Entity.count
      puts "Multi-Tenancy:"
      puts "  Total Entities: #{total_entities}"
      puts ""
    end

    # Count admin users
    if defined?(AdminUser)
      admin_count = AdminUser.count
      super_admin_count = AdminUser.where(role: :super_admin).count rescue 0

      puts "Admin Access:"
      puts "  Total Admin Users: #{admin_count}"
      puts "  Super Admins: #{super_admin_count}"
      puts ""
    end

    puts "Run 'rails security:audit' for detailed security analysis"
  end
end
