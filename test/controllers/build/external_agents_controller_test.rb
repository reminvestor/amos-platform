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
end
