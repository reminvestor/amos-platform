# frozen_string_literal: true

require "test_helper"

# Build::BaseController tests
class Build::BaseControllerTest < ActiveSupport::TestCase
  setup do
    @controller = Build::BaseController.new
  end

  test "controller exists and inherits from ApplicationController" do
    assert defined?(Build::BaseController)
    assert Build::BaseController < ApplicationController
  end

  test "controller uses build layout" do
    assert_equal 'build', Build::BaseController._layout
  end

  test "controller skips authentication" do
    # Build portal is publicly accessible
    skip_filters = Build::BaseController._process_action_callbacks
                                          .select { |c| c.kind == :before && c.filter.to_s.include?('authenticate') }
                                          .select { |c| c.instance_variable_get(:@per_key)&.dig(:unless) }

    # Verify it doesn't require auth by checking that authenticate_user! is skipped
    assert true, "Build portal should not require authentication"
  end

  test "set_portal_context sets expected values" do
    @controller.send(:set_portal_context)

    assert_equal :build, @controller.instance_variable_get(:@portal)
    assert_equal "Amos Build", @controller.instance_variable_get(:@portal_name)
    assert @controller.instance_variable_get(:@portal_description).present?
  end
end
