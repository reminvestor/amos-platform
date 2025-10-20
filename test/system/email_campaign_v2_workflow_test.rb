require "application_system_test_case"

class EmailCampaignV2WorkflowTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @user.update!(entity: @entity)
    sign_in @user
  end

  # Test single message with all required info
  test "creating email campaign with complete info in one message" do
    initial_count = Campaign.where(entity: @entity).count

    # Start workflow with all info provided
    session_id = start_chat_session
    response = send_message(
      session_id,
      "Create an email campaign called Spring Sale 2024 to drive Q2 revenue"
    )

    # Should extract both campaign_name and campaign_goal
    # Workflow should complete all 3 phases
    assert response[:success], "Workflow should succeed"

    # Wait for workflow to complete (max 30 seconds)
    wait_for_workflow_completion(session_id, timeout: 30)

    # Verify campaign was created
    campaign = Campaign.where(entity: @entity).order(:created_at).last
    assert_not_nil campaign, "Campaign should be created"
    assert_equal "Spring Sale 2024", campaign.name
    assert_match /Q2 revenue|drive.*revenue/i, campaign.description
    assert_equal "draft", campaign.status

    # Verify count increased
    assert_equal initial_count + 1, Campaign.where(entity: @entity).count
  end

  # Test multi-turn conversation
  test "creating email campaign through multi-turn conversation" do
    initial_count = Campaign.where(entity: @entity).count

    session_id = start_chat_session

    # Step 1: Start workflow without complete info
    response1 = send_message(session_id, "Create an email campaign")

    # Should ask for campaign name
    assert response1[:awaiting_input], "Should be awaiting input"
    assert_match /name|call it/i, response1[:message]

    # Step 2: Provide campaign name
    response2 = send_message(session_id, "Summer Promo")

    # Should ask for campaign goal (still awaiting input)
    assert response2[:awaiting_input], "Should still be awaiting input"
    assert_match /goal|purpose|achieve/i, response2[:message]

    # Step 3: Provide campaign goal
    response3 = send_message(session_id, "Increase summer sales by 20%")

    # Should complete workflow
    wait_for_workflow_completion(session_id, timeout: 30)

    # Verify campaign was created with correct data
    campaign = Campaign.where(entity: @entity).order(:created_at).last
    assert_not_nil campaign, "Campaign should be created"
    assert_equal "Summer Promo", campaign.name
    assert_match /summer sales|20%/i, campaign.description

    assert_equal initial_count + 1, Campaign.where(entity: @entity).count
  end

  # Test that gathered data persists across turns
  test "workflow context persists across conversation turns" do
    session_id = start_chat_session

    # Start workflow
    send_message(session_id, "Create an email campaign")

    # Provide first piece of info
    send_message(session_id, "Holiday Campaign 2024")

    # Get workflow execution
    task_session = TaskSession.find_by(metadata: { 'session_id' => session_id })
    workflow_execution = WorkflowExecution.find_by(task_session: task_session)

    # Verify campaign_name was stored
    campaign_name_context = workflow_execution.workflow_contexts
      .find_by("key LIKE ?", "%campaign_name%")

    assert_not_nil campaign_name_context, "Campaign name should be stored in context"
    assert_equal "Holiday Campaign 2024", campaign_name_context.value

    # Provide second piece of info
    send_message(session_id, "Drive holiday shopping")

    # Verify both pieces are now stored
    campaign_goal_context = workflow_execution.workflow_contexts
      .find_by("key LIKE ?", "%campaign_goal%")

    assert_not_nil campaign_goal_context, "Campaign goal should be stored in context"
    assert_match /holiday shopping/i, campaign_goal_context.value
  end

  # Test that Phase 2 uses correct data from Phase 1
  test "phase 2 creates campaign with data from phase 1" do
    session_id = start_chat_session

    # Provide complete info
    send_message(session_id, "Create an email campaign called Test Campaign to test the system")

    wait_for_workflow_completion(session_id, timeout: 30)

    # Get the created campaign
    campaign = Campaign.where(entity: @entity).order(:created_at).last

    # Verify it used the exact data we provided
    assert_equal "Test Campaign", campaign.name
    assert_match /test.*system/i, campaign.description

    # Verify it's not using data from previous executions
    assert_not_equal "Test Company Email Campaign", campaign.name
    assert_not_equal "Summer Promo", campaign.name
  end

  # Test workflow isolation - multiple campaigns don't interfere
  test "multiple sequential campaign creations are isolated" do
    session_id = start_chat_session

    # Create first campaign
    send_message(session_id, "Create campaign Alpha for product launch")
    wait_for_workflow_completion(session_id, timeout: 30)

    campaign1 = Campaign.where(entity: @entity).order(:created_at).last
    assert_equal "Alpha", campaign1.name

    # Create second campaign in same session
    send_message(session_id, "Create campaign Beta for customer retention")
    wait_for_workflow_completion(session_id, timeout: 30)

    campaign2 = Campaign.where(entity: @entity).order(:created_at).last
    assert_equal "Beta", campaign2.name
    assert_not_equal campaign1.id, campaign2.id

    # Verify second campaign doesn't have data from first
    assert_match /retention/i, campaign2.description
    assert_no_match /launch/i, campaign2.description
  end

  # Test validation phase catches issues
  test "validation phase runs and reports status" do
    session_id = start_chat_session

    send_message(session_id, "Create campaign Validation Test to verify quality")

    # Wait and check workflow execution
    task_session = TaskSession.find_by(metadata: { 'session_id' => session_id })
    workflow_execution = wait_for_workflow_completion(session_id, timeout: 30)

    # Check that validation phase ran
    validation_results = workflow_execution.workflow_contexts
      .find_by("key LIKE ?", "%verification_validation_results%")

    assert_not_nil validation_results, "Validation results should be stored"

    # Should have completed successfully despite validation warnings
    assert_equal "completed", workflow_execution.status
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Log in"
  end

  def start_chat_session
    # Generate session ID
    SecureRandom.uuid
  end

  def send_message(session_id, message)
    # Use InteractiveTaskService directly (simulating the controller)
    service = InteractiveTaskService.new(@user, @entity, session_id)
    service.process_message(message, [], nil)
  end

  def wait_for_workflow_completion(session_id, timeout: 30)
    start_time = Time.current

    loop do
      task_session = TaskSession.find_by(metadata: { 'session_id' => session_id })
      return nil unless task_session

      workflow_execution = WorkflowExecution.find_by(task_session: task_session)
      return workflow_execution if workflow_execution&.status == "completed"

      if Time.current - start_time > timeout
        flunk "Workflow did not complete within #{timeout} seconds. Status: #{workflow_execution&.status}"
      end

      sleep 0.5
    end
  end
end
