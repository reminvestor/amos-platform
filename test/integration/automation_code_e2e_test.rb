# frozen_string_literal: true

require 'test_helper'

# End-to-end tests for the Deterministic Automation system
#
# These tests verify the complete flow:
# 1. Creating automations with AI-generated code
# 2. Testing automations in sandbox
# 3. Triggering automations from record events
# 4. Execution tracking and error handling
#
class AutomationCodeE2eTest < ActionDispatch::IntegrationTest
  fixtures :entities, :users, :automation_codes, :automation_executions

  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ============================================
  # FULL LIFECYCLE TEST
  # ============================================

  test "complete automation lifecycle: create -> test -> activate -> execute" do
    # Step 1: Create an automation
    automation = AutomationCode.create!(
      entity: @entity,
      created_by: @user,
      name: 'E2E Test Automation',
      description: 'Test the full lifecycle',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          name = default(record[:name], 'Unknown')
          log("Processing: \#{name}")
          
          {
            success: true,
            message: "Processed \#{name}",
            timestamp: now.to_s
          }
        end
      RUBY
    )

    assert automation.persisted?
    assert automation.draft?
    assert_not automation.is_tested?

    # Step 2: Test the automation
    test_result = automation.test!({ record: { name: 'Test Item' } })

    assert test_result[:success], "Test should succeed: #{test_result[:error]}"
    assert_includes test_result[:data][:message], 'Test Item'
    assert automation.reload.is_tested?
    assert automation.testing?

    # Step 3: Activate the automation
    automation.activate!
    assert automation.active?

    # Step 4: Execute the automation
    executor = AutomationCodeExecutor.new(automation, user: @user)
    result = executor.execute!({ record: { name: 'Production Item' } })

    assert result[:success], "Execution should succeed: #{result[:error]}"
    assert_includes result[:data][:message], 'Production Item'
    assert_not_nil result[:execution_id]

    # Step 5: Verify execution was recorded
    execution = AutomationExecution.find(result[:execution_id])
    assert execution.success?
    assert execution.duration_ms.present?

    # Step 6: Verify automation stats updated
    automation.reload
    assert automation.execution_count >= 1
    assert automation.success_count >= 1
    assert_not_nil automation.last_executed_at
  end

  # ============================================
  # TRIGGER MATCHING TESTS
  # ============================================

  test "status_changed automation fires only for matching transitions" do
    automation = AutomationCode.create!(
      entity: @entity,
      name: 'Publish Notification',
      trigger_type: 'status_changed',
      trigger_config: { 'from' => 'draft', 'to' => 'published' },
      code: 'def execute(trigger_data); { success: true }; end',
      status: 'active',
      is_tested: true
    )

    executor = AutomationCodeExecutor.new(automation)

    # Should fire for draft -> published
    assert executor.should_fire?('record_updated', {
      changes: { 'status' => ['draft', 'published'] }
    })

    # Should NOT fire for review -> published
    assert_not executor.should_fire?('record_updated', {
      changes: { 'status' => ['review', 'published'] }
    })

    # Should NOT fire for draft -> review
    assert_not executor.should_fire?('record_updated', {
      changes: { 'status' => ['draft', 'review'] }
    })

    # Should NOT fire for record_created
    assert_not executor.should_fire?('record_created', {
      changes: { 'status' => ['draft', 'published'] }
    })
  end

  test "field_changed automation fires only for matching field" do
    automation = AutomationCode.create!(
      entity: @entity,
      name: 'Priority Changed',
      trigger_type: 'field_changed',
      trigger_config: { 'field' => 'priority' },
      code: 'def execute(trigger_data); { success: true }; end',
      status: 'active',
      is_tested: true
    )

    executor = AutomationCodeExecutor.new(automation)

    # Should fire for priority change
    assert executor.should_fire?('record_updated', {
      changes: { 'priority' => ['low', 'high'] }
    })

    # Should NOT fire for status change
    assert_not executor.should_fire?('record_updated', {
      changes: { 'status' => ['draft', 'published'] }
    })
  end

  # ============================================
  # NOTIFICATION TESTS (MOCKED)
  # ============================================

  test "automation can send notifications" do
    # Create automation that sends Hub notification
    automation = AutomationCode.create!(
      entity: @entity,
      created_by: @user,
      name: 'Notification Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          result = notify_user(
            user_id: trigger_data[:user_id],
            message: "Test notification",
            type: 'info'
          )
          
          { success: result[:success], notification_id: result[:notification_id] }
        end
      RUBY,
      is_tested: true,
      status: 'active'
    )

    executor = AutomationCodeExecutor.new(automation, user: @user)
    
    # Mock HubNotification to avoid actual DB hit
    HubNotification.expects(:create!).returns(OpenStruct.new(id: 999)).once

    result = executor.execute!({ user_id: @user.id })

    assert result[:success], "Should succeed: #{result[:error]}"
  end

  # ============================================
  # ERROR HANDLING TESTS
  # ============================================

  test "automation handles runtime errors gracefully" do
    automation = AutomationCode.create!(
      entity: @entity,
      name: 'Error Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          # This will raise an error
          undefined_variable.to_s
        end
      RUBY,
      is_tested: true,  # Pretend it was tested
      status: 'active'
    )

    executor = AutomationCodeExecutor.new(automation)
    result = executor.execute!({})

    assert_not result[:success]
    assert result[:error].present?

    # Error should be recorded
    automation.reload
    assert automation.error_count >= 1
    assert automation.last_error_message.present?
  end

  test "automation does not execute when paused" do
    automation = automation_codes(:paused_automation)
    
    executor = AutomationCodeExecutor.new(automation)
    result = executor.execute!({})

    assert_not result[:success]
    assert_includes result[:error], 'not active'
  end

  test "automation does not execute when draft" do
    automation = automation_codes(:draft_email_automation)
    
    executor = AutomationCodeExecutor.new(automation)
    result = executor.execute!({})

    assert_not result[:success]
    assert_includes result[:error], 'not active'
  end

  # ============================================
  # RATE LIMITING TESTS
  # ============================================

  test "automation respects notification rate limit" do
    automation = AutomationCode.create!(
      entity: @entity,
      name: 'Rate Limit Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          # Try to send 15 notifications (limit is 10)
          15.times do |i|
            notify_user(user_id: 1, message: "Notification \#{i}", type: 'info')
          end
          { success: true }
        end
      RUBY,
      is_tested: true,
      status: 'active'
    )

    # Mock to track call count
    call_count = 0
    HubNotification.stubs(:create!).returns(OpenStruct.new(id: 1)).with do
      call_count += 1
      true
    end

    executor = AutomationCodeExecutor.new(automation)
    result = executor.execute!({})

    # Should fail due to rate limit
    assert_not result[:success]
    assert_includes result[:error], 'limit exceeded'
  end

  # ============================================
  # EXECUTION AUDIT TRAIL
  # ============================================

  test "execution creates audit trail" do
    automation = automation_codes(:active_notify_on_publish)
    original_execution_count = AutomationExecution.count

    executor = AutomationCodeExecutor.new(automation, user: @user, trigger_source: 'record')
    result = executor.execute!({
      record: { id: 1, title: 'Test', status: 'published' },
      changes: { 'status' => ['draft', 'published'] }
    })

    # Execution record should be created
    assert_equal original_execution_count + 1, AutomationExecution.count

    execution = AutomationExecution.last
    assert_equal automation.id, execution.automation_code_id
    assert_equal @entity.id, execution.entity_id
    assert_equal @user.id, execution.triggered_by_id
    assert_equal 'record', execution.trigger_source
    assert execution.trigger_data.present?
    assert execution.execution_result.present?
    assert execution.duration_ms.present?
  end

  # ============================================
  # DRY RUN / TEST MODE
  # ============================================

  test "dry run does not update automation stats" do
    automation = automation_codes(:active_notify_on_publish)
    original_count = automation.execution_count

    executor = AutomationCodeExecutor.new(automation, dry_run: true)
    result = executor.test!({ record: { title: 'Test' } })

    assert result[:success] || result[:error].present?  # Either way, should complete
    assert_equal original_count, automation.reload.execution_count  # Stats not updated
  end

  # ============================================
  # JOB INTEGRATION
  # ============================================

  test "AutomationTriggerJob executes automation" do
    automation = automation_codes(:simple_log_automation)
    original_count = automation.execution_count

    # Run the job directly (not async)
    AutomationTriggerJob.perform_now(
      automation.id,
      { record: { name: 'Job Test' } },
      { trigger_source: 'test' }
    )

    # Stats should be updated
    assert_equal original_count + 1, automation.reload.execution_count
  end

  test "AutomationTriggerJob skips inactive automations" do
    automation = automation_codes(:paused_automation)
    original_count = automation.execution_count

    # Should not raise, just skip
    AutomationTriggerJob.perform_now(automation.id, {}, {})

    # Stats should NOT be updated
    assert_equal original_count, automation.reload.execution_count
  end

  test "AutomationTriggerJob handles missing automation" do
    # Should not raise
    AutomationTriggerJob.perform_now(999999, {}, {})
  end

  # ============================================
  # COMPLEX WORKFLOW TEST
  # ============================================

  test "automation with multiple actions" do
    automation = AutomationCode.create!(
      entity: @entity,
      name: 'Complex Workflow',
      trigger_type: 'record_created',
      code: <<~RUBY
        def execute(trigger_data)
          # Get record data
          name = record[:name]
          email = record[:email]
          
          # Validate
          return { success: false, error: 'Name required' } if blank?(name)
          
          # Format data
          formatted_name = titleize(name)
          slug = slugify(name)
          
          # Log the action
          log("Processing new record: \#{formatted_name}")
          
          # Return summary
          {
            success: true,
            message: "Processed \#{formatted_name}",
            data: {
              original_name: name,
              formatted_name: formatted_name,
              slug: slug,
              processed_at: format_date(today)
            }
          }
        end
      RUBY,
      is_tested: true,
      status: 'active'
    )

    executor = AutomationCodeExecutor.new(automation)
    
    # Test with valid data
    result = executor.execute!({
      record: { name: 'john doe', email: 'john@example.com' }
    })

    assert result[:success]
    assert_equal 'John Doe', result[:data][:data][:formatted_name]
    assert_equal 'john-doe', result[:data][:data][:slug]

    # Test with missing name
    result = executor.execute!({
      record: { email: 'jane@example.com' }
    })

    assert_not result[:success]
    assert_includes result[:error] || result[:data][:error], 'Name required'
  end
end

