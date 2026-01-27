ENV["RAILS_ENV"] ||= "test"

# ═══════════════════════════════════════════════════════════════════════════
# Test Coverage (must be at the very top, before loading app code)
# Enable with: COVERAGE=true bin/rails test
# ═══════════════════════════════════════════════════════════════════════════
if ENV["COVERAGE"]
  require "simplecov"
  
  SimpleCov.start "rails" do
    # Group files for better organization
    add_group "Services", "app/services"
    add_group "Models", "app/models"
    add_group "Controllers", "app/controllers"
    add_group "Jobs", "app/jobs"
    add_group "Mailers", "app/mailers"
    add_group "Helpers", "app/helpers"
    
    # Critical paths we care most about
    add_group "Living Platform", "app/services/living_platform"
    add_group "Experience Learning", ["app/services/learning", "app/models/task_experience.rb"]
    add_group "Context Graph", "app/services/context_graph"
    
    # Ignore test files and vendored code
    add_filter "/test/"
    add_filter "/vendor/"
    add_filter "/config/"
    add_filter "/db/"
    
    # Set minimum coverage (warn if below)
    # Starting low for CI pipeline setup - increase as coverage improves
    minimum_coverage 15
    minimum_coverage_by_file 5
    
    # Enable branch coverage
    enable_coverage :branch
    
    # Formatter for CI
    if ENV["CI"]
      require "simplecov-cobertura"
      formatter SimpleCov::Formatter::MultiFormatter.new([
        SimpleCov::Formatter::HTMLFormatter,
        SimpleCov::Formatter::CoberturaFormatter
      ])
    end
  end
  
  puts "📊 SimpleCov coverage enabled"
end

require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"
require "minitest/mock"

# Configure Capybara for CI environments
Capybara.configure do |config|
  # Increase timeouts for slower CI environments
  config.default_max_wait_time = 10

  # Use puma server for system tests
  config.server = :puma, { Silent: true }
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with processes
    # Use limited workers to avoid database ownership issues in Docker
    parallelize(workers: ENV.fetch('PARALLEL_WORKERS', 4).to_i, with: :processes, threshold: 50)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Test helpers for creating valid test data
    def create_valid_user(attributes = {})
      defaults = {
        first_name: "Test",
        last_name: "User",
        role: "admin",
        email: "test#{SecureRandom.hex(4)}@example.com",
        password: "password123",
        password_confirmation: "password123"
      }

      entity = attributes.delete(:entity) || entities(:one)
      User.create!(defaults.merge(attributes).merge(entity: entity))
    end

    def create_valid_admin_user(attributes = {})
      defaults = {
        first_name: "Admin",
        last_name: "User",
        role: :super_admin,
        email: "admin#{SecureRandom.hex(4)}@example.com",
        password: "password123"
      }

      AdminUser.create!(defaults.merge(attributes))
    end
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
