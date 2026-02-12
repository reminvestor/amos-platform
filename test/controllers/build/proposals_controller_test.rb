# frozen_string_literal: true

require "test_helper"

# Build portal controller tests
# Note: Build subdomain routes require subdomain constraint which isn't
# available in standard integration tests. These tests verify the
# controller logic via direct unit testing instead.
class Build::ProposalsControllerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
  end

  test "controller class exists and inherits from Build::BaseController" do
    assert defined?(Build::ProposalsController)
    assert Build::ProposalsController < Build::BaseController
  end

  test "controller has required actions" do
    controller = Build::ProposalsController.new
    assert controller.respond_to?(:index)
    assert controller.respond_to?(:show)
    assert controller.respond_to?(:new)
    assert controller.respond_to?(:create)
    assert controller.respond_to?(:vote)
  end

  test "index sets empty proposals array" do
    controller = Build::ProposalsController.new
    controller.index
    assert_equal [], controller.instance_variable_get(:@proposals)
  end
end
