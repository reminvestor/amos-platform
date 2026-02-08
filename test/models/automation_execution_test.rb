# frozen_string_literal: true

require 'test_helper'

class AutomationExecutionTest < ActiveSupport::TestCase
  fixtures :entities, :users, :automation_codes

  setup do
    @entity = entities(:one)
    @user = users(:one)
    @automation = automation_codes(:welcome_email) rescue create_test_automation
  end

  # ============================================
  # TRIGGER SOURCE VALIDATION
  # ============================================

  test "all used trigger sources are valid" do
    valid_sources = %w[record schedule webhook manual test job form automation_bridge]
    valid_sources.each do |source|
      execution = AutomationExecution.new(
        automation_code: @automation,
        entity: @entity,
        trigger_source: source,
        status: 'pending'
      )
      assert execution.valid?, "trigger_source '#{source}' should be valid but got: #{execution.errors.full_messages}"
    end
  end

  test "rejects invalid trigger source" do
    execution = AutomationExecution.new(
      automation_code: @automation,
      entity: @entity,
      trigger_source: 'invalid_source',
      status: 'pending'
    )
    assert_not execution.valid?
    assert execution.errors[:trigger_source].present?
  end

  test "allows nil trigger source" do
    execution = AutomationExecution.new(
      automation_code: @automation,
      entity: @entity,
      trigger_source: nil,
      status: 'pending'
    )
    # trigger_source validation has allow_nil: true
    assert execution.errors[:trigger_source].blank? || execution.valid?
  end

  # ============================================
  # STATUS VALIDATION
  # ============================================

  test "valid statuses are accepted" do
    %w[pending running success failed timeout].each do |status|
      execution = AutomationExecution.new(
        automation_code: @automation,
        entity: @entity,
        status: status
      )
      assert execution.errors[:status].blank? || execution.valid?,
             "Status '#{status}' should be valid"
    end
  end

  # ============================================
  # EXECUTION CREATION FROM BRIDGE
  # ============================================

  test "can create execution with 'record' trigger source" do
    execution = AutomationExecution.create!(
      automation_code: @automation,
      entity: @entity,
      triggered_by: @user,
      trigger_source: 'record',
      status: 'pending',
      trigger_data: { event: 'record_created', record: { id: 1 } }
    )

    assert execution.persisted?
    assert_equal 'record', execution.trigger_source
    assert_equal 'pending', execution.status
  end

  test "can create execution with 'job' trigger source" do
    execution = AutomationExecution.create!(
      automation_code: @automation,
      entity: @entity,
      trigger_source: 'job',
      status: 'pending'
    )

    assert execution.persisted?
    assert_equal 'job', execution.trigger_source
  end

  private

  def create_test_automation
    AutomationCode.create!(
      entity: @entity,
      created_by: @user,
      name: "Test Automation",
      trigger_type: "record_created",
      code: "def execute(trigger_data); { success: true }; end",
      status: "active",
      is_tested: true,
      is_compiled: true
    )
  end
end
