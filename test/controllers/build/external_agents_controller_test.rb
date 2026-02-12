# frozen_string_literal: true

require 'test_helper'

# Build portal controller tests
# Note: Build subdomain routes require subdomain constraint which isn't
# available in standard integration tests. These tests verify the
# controller logic via direct unit testing instead.
class Build::ExternalAgentsControllerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
  end

  test "controller class exists and inherits from Build::BaseController" do
    assert defined?(Build::ExternalAgentsController)
    assert Build::ExternalAgentsController < Build::BaseController
  end

  test "controller has required actions" do
    controller = Build::ExternalAgentsController.new
    assert controller.respond_to?(:index)
    assert controller.respond_to?(:show)
    assert controller.respond_to?(:register)
    assert controller.respond_to?(:reviews)
    assert controller.respond_to?(:approve_review)
    assert controller.respond_to?(:reject_review)
    assert controller.respond_to?(:suspend)
    assert controller.respond_to?(:reactivate)
    assert controller.respond_to?(:configure_webhook)
  end

  # --- Public access (index and show do NOT require auth) ---

  test "authentication is only required for write actions" do
    # Verify index and show are public by checking the controller source
    source_file, = Build::ExternalAgentsController.instance_method(:index).source_location
    source = File.read(source_file)

    # The before_action should exclude index and show
    assert_match(/require_authentication!.*except.*\[:index.*:show\]/, source)
  end

  test "index queries all active agents not scoped to a user" do
    # Verify the index method queries ExternalAgentRegistration directly
    source_file, = Build::ExternalAgentsController.instance_method(:index).source_location
    source = File.read(source_file)

    # Extract index method body (between "def index" and next "def " or "private")
    index_method = source[/def index\b.*?(?=\n\s+def |\n\s+private)/m]
    assert_not_nil index_method, "Could not extract index method from source"
    assert_match(/ExternalAgentRegistration/, index_method)
    assert_no_match(/current_user\.external_agent_registrations/, index_method)
  end

  test "index returns empty stats on error" do
    controller = Build::ExternalAgentsController.new

    # Simulate ExternalAgentRegistration not existing or table missing
    ExternalAgentRegistration.stubs(:where).raises(StandardError.new("table missing"))

    # The rescue block should set safe defaults
    controller.index rescue nil
    agents = controller.instance_variable_get(:@agents)
    stats = controller.instance_variable_get(:@stats)

    assert_equal [], agents
    assert_equal 0, stats[:active_agents]
    assert_equal 0, stats[:total_completed]
    assert_equal 0, stats[:total_earned]
    assert_equal 0, stats[:pending_reviews]
  end

  test "show finds agent by id without requiring current_user" do
    # The show action uses ExternalAgentRegistration.find(params[:id])
    # not current_user.external_agent_registrations.find()
    source = Build::ExternalAgentsController.instance_method(:show).source_location
    source_file = File.read(source[0])
    show_method = source_file[/def show.*?(?=def |\z)/m]

    # Verify it uses the public finder, not user-scoped
    assert_match(/ExternalAgentRegistration\.find/, show_method)
    assert_no_match(/current_user\.external_agent_registrations/, show_method)
  end
end
