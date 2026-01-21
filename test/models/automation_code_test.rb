# frozen_string_literal: true

require 'test_helper'

class AutomationCodeTest < ActiveSupport::TestCase
  fixtures :entities, :users, :automation_codes

  # ============================================
  # VALIDATIONS
  # ============================================

  test "requires name" do
    automation = AutomationCode.new(
      entity: entities(:one),
      trigger_type: 'record_created',
      code: 'def execute(trigger_data); end'
    )
    assert_not automation.valid?
    assert_includes automation.errors[:name], "can't be blank"
  end

  test "requires trigger_type" do
    automation = AutomationCode.new(
      entity: entities(:one),
      name: 'Test',
      code: 'def execute(trigger_data); end'
    )
    assert_not automation.valid?
    assert_includes automation.errors[:trigger_type], "can't be blank"
  end

  test "validates trigger_type inclusion" do
    automation = AutomationCode.new(
      entity: entities(:one),
      name: 'Test',
      trigger_type: 'invalid_type',
      code: 'def execute(trigger_data); end'
    )
    assert_not automation.valid?
    assert_includes automation.errors[:trigger_type], "is not included in the list"
  end

  test "validates status inclusion" do
    automation = AutomationCode.new(
      entity: entities(:one),
      name: 'Test',
      trigger_type: 'record_created',
      code: 'def execute(trigger_data); end',
      status: 'invalid'
    )
    assert_not automation.valid?
    assert_includes automation.errors[:status], "is not included in the list"
  end

  test "validates code syntax" do
    automation = AutomationCode.new(
      entity: entities(:one),
      name: 'Bad Syntax',
      trigger_type: 'manual',
      code: 'def execute(trigger_data'  # Missing closing paren and end
    )
    assert_not automation.valid?
    assert automation.errors[:code].any?
  end

  test "validates status_changed trigger requires config" do
    automation = AutomationCode.new(
      entity: entities(:one),
      name: 'Status Change',
      trigger_type: 'status_changed',
      trigger_config: {},
      code: 'def execute(trigger_data); end'
    )
    assert_not automation.valid?
    assert automation.errors[:trigger_config].any?
  end

  test "validates field_changed trigger requires field" do
    automation = AutomationCode.new(
      entity: entities(:one),
      name: 'Field Change',
      trigger_type: 'field_changed',
      trigger_config: {},
      code: 'def execute(trigger_data); end'
    )
    assert_not automation.valid?
    assert automation.errors[:trigger_config].any?
  end

  test "generates unique slug from name" do
    automation1 = AutomationCode.create!(
      entity: entities(:one),
      name: 'My Automation',
      trigger_type: 'manual',
      code: 'def execute(trigger_data); { success: true }; end'
    )
    assert_equal 'my-automation', automation1.slug

    automation2 = AutomationCode.create!(
      entity: entities(:one),
      name: 'My Automation',
      trigger_type: 'manual',
      code: 'def execute(trigger_data); { success: true }; end'
    )
    assert_equal 'my-automation-1', automation2.slug
  end

  # ============================================
  # STATUS HELPERS
  # ============================================

  test "status helper methods work correctly" do
    assert automation_codes(:active_notify_on_publish).active?
    assert automation_codes(:draft_email_automation).draft?
    assert automation_codes(:paused_automation).paused?
  end

  test "can_activate? returns true for tested draft automations" do
    automation = automation_codes(:draft_email_automation)
    assert_not automation.can_activate?  # Not tested

    automation.update!(is_tested: true)
    assert automation.can_activate?
  end

  test "activate! raises for untested automations" do
    automation = automation_codes(:draft_email_automation)
    
    assert_raises(AutomationCode::InvalidTransition) do
      automation.activate!
    end
  end

  test "activate! works for tested automations" do
    automation = automation_codes(:draft_email_automation)
    automation.update!(is_tested: true, status: 'testing')
    
    automation.activate!
    assert automation.active?
  end

  test "pause! works for active automations" do
    automation = automation_codes(:active_notify_on_publish)
    automation.pause!
    assert automation.paused?
  end

  test "pause! raises for non-active automations" do
    automation = automation_codes(:draft_email_automation)
    
    assert_raises(AutomationCode::InvalidTransition) do
      automation.pause!
    end
  end

  # ============================================
  # EXECUTION TRACKING
  # ============================================

  test "record_execution! updates counters on success" do
    automation = automation_codes(:active_notify_on_publish)
    original_count = automation.execution_count
    original_success = automation.success_count

    automation.record_execution!({ success: true }, duration_ms: 50)

    assert_equal original_count + 1, automation.execution_count
    assert_equal original_success + 1, automation.success_count
    assert_not_nil automation.last_executed_at
  end

  test "record_execution! updates counters on failure" do
    automation = automation_codes(:active_notify_on_publish)
    original_count = automation.execution_count
    original_errors = automation.error_count

    automation.record_execution!({ success: false, error: 'Test error' }, duration_ms: 100)

    assert_equal original_count + 1, automation.execution_count
    assert_equal original_errors + 1, automation.error_count
    assert_equal 'Test error', automation.last_error_message
  end

  test "error_rate and success_rate calculations" do
    automation = automation_codes(:paused_automation)
    
    # 85 successes, 15 errors out of 100
    assert_in_delta 0.15, automation.error_rate, 0.01
    assert_in_delta 0.85, automation.success_rate, 0.01
  end

  test "auto-pauses on high error rate" do
    automation = AutomationCode.create!(
      entity: entities(:one),
      name: 'Error Prone',
      trigger_type: 'manual',
      code: 'def execute(trigger_data); end',
      status: 'active',
      is_tested: true,
      execution_count: 10,
      error_count: 5
    )

    # This will push error rate over 50%
    automation.record_error!(StandardError.new('Another error'))

    assert_equal 'paused', automation.reload.status
  end

  # ============================================
  # TRIGGER MATCHING
  # ============================================

  test "matches_trigger? for status_changed with exact match" do
    automation = automation_codes(:active_notify_on_publish)
    
    # Exact match: draft -> published
    event_data = { changes: { 'status' => ['draft', 'published'] } }
    assert automation.matches_trigger?(event_data)

    # Wrong transition
    event_data = { changes: { 'status' => ['review', 'published'] } }
    assert_not automation.matches_trigger?(event_data)
  end

  test "matches_trigger? for status_changed with partial config" do
    automation = AutomationCode.new(
      trigger_type: 'status_changed',
      trigger_config: { 'to' => 'published' }  # Only 'to' specified
    )

    # Should match any -> published
    event_data = { changes: { 'status' => ['anything', 'published'] } }
    assert automation.matches_trigger?(event_data)
  end

  test "matches_trigger? for field_changed" do
    automation = AutomationCode.new(
      trigger_type: 'field_changed',
      trigger_config: { 'field' => 'priority' }
    )

    # Field changed
    event_data = { changes: { 'priority' => ['low', 'high'] } }
    assert automation.matches_trigger?(event_data)

    # Different field changed
    event_data = { changes: { 'status' => ['draft', 'published'] } }
    assert_not automation.matches_trigger?(event_data)
  end

  # ============================================
  # SCOPES
  # ============================================

  test "active scope returns only active automations" do
    AutomationCode.active.each do |automation|
      assert_equal 'active', automation.status
    end
  end

  test "for_entity scope filters correctly" do
    entity = entities(:one)
    AutomationCode.for_entity(entity.id).each do |automation|
      assert_equal entity.id, automation.entity_id
    end
  end

  test "for_trigger scope filters by trigger type" do
    AutomationCode.for_trigger('status_changed').each do |automation|
      assert_equal 'status_changed', automation.trigger_type
    end
  end

  # ============================================
  # SERIALIZATION
  # ============================================

  test "to_preview returns expected structure" do
    automation = automation_codes(:active_notify_on_publish)
    preview = automation.to_preview

    assert_equal automation.id, preview[:id]
    assert_equal automation.name, preview[:name]
    assert_equal automation.trigger_type, preview[:trigger_type]
    assert_equal automation.status, preview[:status]
    assert preview[:trigger_description].present?
    assert preview[:success_rate].present?
  end

  test "trigger_description generates readable text" do
    automation = automation_codes(:active_notify_on_publish)
    desc = automation.trigger_description

    assert_includes desc.downcase, 'status changes'
    assert_includes desc.downcase, 'draft'
    assert_includes desc.downcase, 'published'
  end
end

