ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

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
