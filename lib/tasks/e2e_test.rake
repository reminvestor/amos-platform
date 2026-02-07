# frozen_string_literal: true

namespace :test do
  desc "Run Scout E2E integration tests (requires Bedrock access)"
  task :e2e => :environment do
    puts "\n" + "=" * 60
    puts "SCOUT E2E INTEGRATION TESTS"
    puts "=" * 60
    puts ""
    puts "These tests hit the actual /scout/chat_stream endpoint"
    puts "and verify database side effects."
    puts ""
    puts "Requirements:"
    puts "  - AWS Bedrock access configured"
    puts "  - Test database with fixtures loaded"
    puts ""

    system("bundle exec rails test test/integration/scout_e2e_test.rb -v") || exit(1)
  end

  desc "Run full test suite: BOB benchmark + E2E tests"
  task :full => :environment do
    puts "\n" + "=" * 60
    puts "FULL TEST SUITE"
    puts "=" * 60
    
    puts "\n--- Phase 1: BOB v4 Quick Benchmark ---"
    Rake::Task["benchmark:bob4:quick"].invoke
    
    puts "\n--- Phase 2: Scout E2E Tests ---"
    system("bundle exec rails test test/integration/scout_e2e_test.rb -v") || exit(1)
    
    puts "\n" + "=" * 60
    puts "ALL TESTS COMPLETE"
    puts "=" * 60
  end
end
