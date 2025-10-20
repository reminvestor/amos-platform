require "test_helper"

# Comprehensive test suite for Email Campaign V2 Workflow System
#
# PERFORMANCE NOTES:
# - These tests make real AWS Bedrock API calls which have variable latency
# - Each test may take 30-90 seconds due to:
#   * AI model inference time (Claude Sonnet 4.5)
#   * Multiple API calls per workflow phase (gather, execute, validate)
#   * Multi-turn conversational tests requiring sequential API calls
#   * Network latency to AWS Bedrock endpoints
# - Full suite runtime: 6-10 minutes (17 tests)
# - For faster testing, consider mocking BedrockService in development
#
class EmailCampaignWorkflowComprehensiveTest < ActiveSupport::TestCase
  # Disable all fixtures for this test - we create our own data
  self.use_transactional_tests = true
  self.use_instantiated_fixtures = false
  self.fixture_table_names = []

  setup do
    # Create entity and user for testing
    @entity = Entity.create!(
      name: "Test Company",
      subdomain: "test-#{SecureRandom.hex(4)}"
    )

    @user = User.create!(
      email: "test-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      entity: @entity
    )

    # Clean up any existing campaigns and workflows
    Campaign.where(entity: @entity).destroy_all
    WorkflowExecution.destroy_all
    TaskSession.destroy_all
  end

  teardown do
    # Clean up created records
    @user&.destroy
    @entity&.destroy
  end

  # ============================================
  # TEST GROUP 1: Single Message Campaign Creation
  # ============================================

  test "creates campaign with all info in single message" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    result = service.process_message(
      "Create an email campaign called Spring Sale 2024 to drive Q2 revenue",
      [],
      nil
    )

    # Verify workflow started
    assert result[:success], "Workflow should start successfully"

    # Wait for completion
    workflow_execution = wait_for_workflow(service.task_session, status: "completed", timeout: 90)
    assert_not_nil workflow_execution, "Workflow should complete"

    # Verify campaign created
    campaign = Campaign.where(entity: @entity).order(:created_at).last
    assert_not_nil campaign, "Campaign should be created"
    assert_equal "Spring Sale 2024", campaign.name
    assert_match /Q2 revenue|drive.*revenue/i, campaign.description
    assert_equal "draft", campaign.status

    # Verify Phase 3 validation passed
    validation_context = workflow_execution.workflow_contexts
      .find_by("key LIKE ?", "%verification_all_passed%")
    assert_equal "true", validation_context&.value, "Validation should pass"
  end

  test "creates campaign with minimal info in single message" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    result = service.process_message(
      "Create a holiday campaign",
      [],
      nil
    )

    workflow_execution = wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    campaign = Campaign.where(entity: @entity).order(:created_at).last
    assert_not_nil campaign
    assert campaign.name.present?
  end

  # ============================================
  # TEST GROUP 2: Multi-Turn Conversation
  # ============================================

  test "creates campaign through multi-turn conversation with missing name" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    # Turn 1: Start without name
    result1 = service.process_message("Create an email campaign", [], nil)

    # Should be awaiting input
    state = service.task_session.state || {}
    assert_equal "awaiting_input", state["workflow_status"], "Should be awaiting input"

    # Turn 2: Provide campaign name
    result2 = service.process_message("Summer Promo", [], nil)

    # Should still be awaiting input (for goal)
    service.task_session.reload
    state = service.task_session.state || {}
    assert_equal "awaiting_input", state["workflow_status"], "Should still be awaiting input"

    # Turn 3: Provide goal
    result3 = service.process_message("Increase summer sales", [], nil)

    # Should complete
    workflow_execution = wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    campaign = Campaign.where(entity: @entity).order(:created_at).last
    assert_equal "Summer Promo", campaign.name
    assert_match /summer sales/i, campaign.description
  end

  test "creates campaign when user provides info in reverse order" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    # Turn 1: Start workflow
    service.process_message("Create an email campaign", [], nil)

    # Turn 2: Provide goal first (unusual order)
    service.process_message("Drive holiday revenue", [], nil)

    # Turn 3: Then provide name
    service.process_message("Holiday Sale 2024", [], nil)

    workflow_execution = wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    campaign = Campaign.where(entity: @entity).order(:created_at).last
    assert_equal "Holiday Sale 2024", campaign.name
    assert_match /holiday revenue/i, campaign.description
  end

  # ============================================
  # TEST GROUP 3: Context Persistence
  # ============================================

  test "workflow context persists across conversation turns" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    # Turn 1: Start workflow
    service.process_message("Create an email campaign", [], nil)

    # Turn 2: Provide first piece of data
    service.process_message("Black Friday Campaign", [], nil)

    # Check that data was stored
    workflow_execution = WorkflowExecution.find_by(task_session: service.task_session)
    campaign_name_context = workflow_execution.workflow_contexts
      .find_by("key LIKE ?", "%campaign_name%")

    assert_not_nil campaign_name_context, "Campaign name should be stored"
    assert_equal "Black Friday Campaign", campaign_name_context.value

    # Turn 3: Provide second piece
    service.process_message("Maximize Black Friday sales", [], nil)

    # Check both pieces are stored
    workflow_execution.reload
    campaign_goal_context = workflow_execution.workflow_contexts
      .find_by("key LIKE ?", "%campaign_goal%")

    assert_not_nil campaign_goal_context, "Campaign goal should be stored"
    assert_match /Black Friday sales/i, campaign_goal_context.value
  end

  test "workflow loads previous gathered data on resume" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    # Start and provide name
    service.process_message("Create an email campaign", [], nil)
    service.process_message("Test Campaign", [], nil)

    # Wait for workflow to start
    sleep 1
    workflow_execution = WorkflowExecution.find_by(task_session: service.task_session)
    assert_not_nil workflow_execution, "Workflow execution should exist"

    # Manually store some context to simulate resume
    WorkflowContext.create!(
      workflow_execution: workflow_execution,
      task_session: service.task_session,
      key: "gather_campaign_details_campaign_name",
      value: "Test Campaign",
      data_type: "extracted_data"
    )

    # Provide goal - should remember the name
    service.process_message("Test goal", [], nil)

    wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    campaign = Campaign.where(entity: @entity).order(:created_at).last
    assert_equal "Test Campaign", campaign.name
  end

  # ============================================
  # TEST GROUP 4: Phase 2 Execution
  # ============================================

  test "phase 2 creates campaign with correct data from phase 1" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    service.process_message(
      "Create campaign Cyber Monday Sale to drive online sales",
      [],
      nil
    )

    workflow_execution = wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    # Check Phase 2 created the campaign
    setup_id_context = workflow_execution.workflow_contexts
      .find_by("key LIKE ?", "%setup_campaign_id%")

    assert_not_nil setup_id_context, "Campaign ID should be stored by Phase 2"

    campaign = Campaign.find(setup_id_context.value.to_i)
    assert_equal "Cyber Monday Sale", campaign.name
    assert_match /online sales/i, campaign.description
  end

  test "phase 2 does not use data from previous workflow executions" do
    # Create first campaign
    session_id1 = SecureRandom.uuid
    service1 = InteractiveTaskService.new(@user, @entity, session_id1)
    service1.process_message("Create campaign Old Campaign with old goal", [], nil)
    wait_for_workflow(service1.task_session, status: "completed", timeout: 90)

    # Create second campaign in NEW session
    session_id2 = SecureRandom.uuid
    service2 = InteractiveTaskService.new(@user, @entity, session_id2)
    service2.process_message("Create campaign New Campaign with new goal", [], nil)
    wait_for_workflow(service2.task_session, status: "completed", timeout: 90)

    # Verify second campaign doesn't have data from first
    campaign = Campaign.where(entity: @entity).order(:created_at).last
    assert_equal "New Campaign", campaign.name
    assert_match /new goal/i, campaign.description
    assert_no_match /old/i, campaign.description.downcase
  end

  # ============================================
  # TEST GROUP 5: Phase 3 Validation
  # ============================================

  test "phase 3 validation passes when campaign is created" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    service.process_message("Create campaign Validation Test to verify quality", [], nil)

    workflow_execution = wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    # Check validation results
    validation_results = workflow_execution.workflow_contexts
      .find_by("key LIKE ?", "%verification_validation_results%")

    assert_not_nil validation_results, "Validation results should be stored"

    results = JSON.parse(validation_results.value)
    assert results.is_a?(Array), "Validation results should be an array"
    assert results.first["passed"] == true, "Validation should pass"
  end

  test "workflow completes successfully despite validation warnings" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    service.process_message("Create basic campaign", [], nil)

    workflow_execution = wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    # Even if validation has warnings, workflow should complete
    assert_equal "completed", workflow_execution.status

    # Campaign should still be created
    campaign = Campaign.where(entity: @entity).order(:created_at).last
    assert_not_nil campaign
  end

  # ============================================
  # TEST GROUP 6: Workflow Isolation
  # ============================================

  test "multiple sequential campaigns are isolated" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    # Create first campaign
    service.process_message("Create campaign Alpha for product launch", [], nil)
    wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    campaign1 = Campaign.where(entity: @entity).order(:created_at).last

    # Create second campaign
    service.process_message("Create campaign Beta for customer retention", [], nil)
    wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    campaign2 = Campaign.where(entity: @entity).order(:created_at).last

    # Verify isolation
    assert_not_equal campaign1.id, campaign2.id
    assert_equal "Alpha", campaign1.name
    assert_equal "Beta", campaign2.name
    assert_match /launch/i, campaign1.description
    assert_match /retention/i, campaign2.description
    assert_no_match /retention/i, campaign1.description
    assert_no_match /launch/i, campaign2.description
  end

  # ============================================
  # TEST GROUP 7: Post-Workflow Conversation
  # ============================================

  test "single word response after workflow does not trigger new workflow" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    # Complete workflow
    service.process_message("Create campaign Test to test system", [], nil)
    wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    initial_count = Campaign.where(entity: @entity).count

    # Send single word that matches workflow keywords
    result = service.process_message("schedule", [], nil)

    # Should NOT create another campaign
    sleep 2 # Give it time if it were to start
    assert_equal initial_count, Campaign.where(entity: @entity).count, "Should not create new campaign"

    # Verify we're in post-workflow mode
    service.task_session.reload
    state = service.task_session.state || {}
    assert_equal true, state["workflow_context_active"], "Should be in post-workflow conversation mode"
  end

  test "new create request after workflow clears post-workflow mode" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    # Complete first workflow
    service.process_message("Create campaign First", [], nil)
    wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    # Verify post-workflow mode is active
    service.task_session.reload
    state = service.task_session.state || {}
    assert_equal true, state["workflow_context_active"]

    # Send new create request
    service.process_message("Create campaign Second", [], nil)

    # Should clear post-workflow mode and start new workflow
    service.task_session.reload
    state = service.task_session.state || {}
    # Mode should be cleared when new action detected
    # and new workflow execution should be created
    new_execution = WorkflowExecution.where(task_session: service.task_session).order(:created_at).last
    assert new_execution.created_at > 2.seconds.ago
  end

  # ============================================
  # TEST GROUP 8: Error Handling
  # ============================================

  test "workflow handles empty user input gracefully" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    service.process_message("Create an email campaign", [], nil)

    # Send empty string
    result = service.process_message("", [], nil)

    # Should still be awaiting input, not crash
    service.task_session.reload
    state = service.task_session.state || {}
    assert_equal "awaiting_input", state["workflow_status"]
  end

  test "workflow handles very long campaign names" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    long_name = "A" * 200
    service.process_message("Create campaign #{long_name} to test limits", [], nil)

    workflow_execution = wait_for_workflow(service.task_session, status: "completed", timeout: 90)

    campaign = Campaign.where(entity: @entity).order(:created_at).last
    # Should either truncate or store full name
    assert_not_nil campaign
    assert campaign.name.present?
  end

  # ============================================
  # TEST GROUP 9: Template Keyword Matching
  # ============================================

  test "show campaign request does not trigger campaign creation workflow" do
    # Create a campaign first
    Campaign.create!(
      entity: @entity,
      user: @user,
      name: "Existing Campaign",
      description: "Test",
      status: "draft"
    )

    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    initial_count = Campaign.where(entity: @entity).count

    # This should NOT trigger workflow
    result = service.process_message("Show me campaign details", [], nil)

    sleep 2
    assert_equal initial_count, Campaign.where(entity: @entity).count, "Should not create new campaign"
  end

  test "view campaign list does not trigger campaign creation workflow" do
    session_id = SecureRandom.uuid
    service = InteractiveTaskService.new(@user, @entity, session_id)

    initial_count = Campaign.where(entity: @entity).count

    result = service.process_message("List all campaigns", [], nil)

    sleep 2
    assert_equal initial_count, Campaign.where(entity: @entity).count
  end

  # ============================================
  # Helper Methods
  # ============================================

  private

  def wait_for_workflow(task_session, status:, timeout: 90)
    start_time = Time.current

    loop do
      workflow_execution = WorkflowExecution.find_by(task_session: task_session)

      if workflow_execution&.status == status
        return workflow_execution
      end

      if Time.current - start_time > timeout
        flunk "Workflow did not reach '#{status}' status within #{timeout} seconds. Current status: #{workflow_execution&.status}"
      end

      sleep 0.5
      task_session.reload
    end
  end
end
