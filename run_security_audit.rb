#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8

# Force UTF-8 encoding
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

# Standalone security audit runner (no Rails required)
require_relative 'lib/security_auditor'

# Mock Rails.root for file path resolution
module Rails
  def self.root
    Pathname.new(File.expand_path('..', __FILE__))
  end

  module LoggerMock
    def self.info(message)
      # No-op for logger
    end
  end

  def self.logger
    LoggerMock
  end
end

class Pathname < String
  def join(*args)
    File.join(self, *args)
  end
end

# Parse command line arguments
category = ARGV[0]
verbose = ARGV.include?('--verbose') || ARGV.include?('-v')
report_file = ARGV.find { |arg| arg.start_with?('--report=') }&.split('=')&.last

# Initialize and run auditor
puts "🔒 AMOS Security Audit"
puts "=" * 60
puts ""

auditor = SecurityAuditor.new(verbose: verbose)

# Run audit
results = if category && !category.start_with?('--')
            puts "Running #{category} category audit...\n"
            auditor.run_category_audit(category)
          else
            auditor.run_full_audit
          end

# Print report
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
