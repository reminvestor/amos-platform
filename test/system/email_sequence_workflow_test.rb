require "application_system_test_case"

class EmailSequenceWorkflowTest < ApplicationSystemTestCase
  setup do
    @user = users(:default)
    @entity = entities(:default)
    @contact_group = contact_groups(:default_group)

    # Ensure contact group has contacts
    assert @contact_group.contacts.any?, "Contact group should have contacts for testing"

    sign_in @user
  end

  teardown do
    # Clean up any generated sequences
    EmailSequence.where(entity: @entity).destroy_all
  end

  # ============================================================================
  # HAPPY PATH TESTS
  # ============================================================================

  test "creating email sequence with AI-generated content through conversational workflow" do
    visit scout_path

    # Initiate email sequence creation
    fill_in "message-input", with: "Create an email sequence for my customers"
    click_button "send-button"

    # Wait for AI response asking for sequence details
    assert_text "sequence", wait: 10

    # Provide sequence name and goal
    fill_in "message-input", with: "Welcome Series to onboard new customers"
    click_button "send-button"

    # AI should ask about contact group
    assert_text "contact group", wait: 10

    # Provide contact group
    fill_in "message-input", with: "Use Default Contact Group"
    click_button "send-button"

    # AI should ask about content strategy
    assert_text "template", wait: 10

    # Choose AI generation
    fill_in "message-input", with: "Have AI generate the content"
    click_button "send-button"

    # AI should ask how many emails
    assert_text "how many", wait: 10

    # Specify 3 emails
    fill_in "message-input", with: "3 emails in the sequence"
    click_button "send-button"

    # AI should ask about timing
    assert_text "timing", wait: 10

    # Provide timing pattern
    fill_in "message-input", with: "Send immediately, then 3 days, then 7 days"
    click_button "send-button"

    # Wait for sequence creation
    assert_text "sequence created", wait: 30

    # Verify database state
    sequence = @entity.email_sequences.last
    assert_not_nil sequence, "EmailSequence should be created"
    assert_equal "draft", sequence.status, "Sequence should be in draft status"
    assert sequence.name.downcase.include?("welcome"), "Sequence name should contain 'welcome'"
    assert_equal @contact_group.id, sequence.contact_group_id, "Sequence should be linked to contact group"

    # Verify sequence steps
    assert_equal 3, sequence.sequence_steps.count, "Should have 3 sequence steps"

    steps = sequence.sequence_steps.ordered
    assert_equal 0, steps.first.delay_hours, "First email should send immediately"
    assert_equal 72, steps.second.delay_hours, "Second email should be delayed 3 days (72 hours)"
    assert_equal 168, steps.third.delay_hours, "Third email should be delayed 7 days (168 hours)"

    # Verify each step has content
    steps.each_with_index do |step, index|
      assert step.subject.present? || step.email_template_id.present?,
             "Step #{index + 1} should have subject or template"
      assert step.body.present? || step.email_template_id.present?,
             "Step #{index + 1} should have body or template"
    end

    # Verify contact enrollments
    assert_equal @contact_group.contacts.count, sequence.sequence_enrollments.count,
                 "All contacts should be enrolled"

    sequence.sequence_enrollments.each do |enrollment|
      assert_equal "pending", enrollment.status, "Enrollment should be pending"
      assert_equal 0, enrollment.current_step_number, "Should start at step 0"
    end

    # Verify success message shown to user
    assert_text "Draft", wait: 5
    assert_text "review", wait: 5
  end

  test "creating email sequence with existing templates" do
    # Create test templates first
    template1 = email_templates(:default_template_1)
    template2 = email_templates(:default_template_2)

    visit scout_path

    # Initiate sequence creation
    fill_in "message-input", with: "Set up an email sequence using my existing templates"
    click_button "send-button"

    # Wait for AI response
    assert_text "sequence", wait: 10

    # Provide details with template preference
    fill_in "message-input", with: "Product Launch Sequence for Default Contact Group using existing templates"
    click_button "send-button"

    # AI should ask about templates or show available ones
    # Give it time to process and respond
    sleep 2

    # Provide template IDs
    fill_in "message-input", with: "Use template #{template1.id} first, then template #{template2.id}"
    click_button "send-button"

    # Provide timing if asked
    sleep 2
    fill_in "message-input", with: "3 days between each email"
    click_button "send-button"

    # Wait for completion
    assert_text "sequence created", wait: 30

    # Verify database
    sequence = @entity.email_sequences.last
    assert_not_nil sequence
    assert_equal 2, sequence.sequence_steps.count

    # Verify templates are linked
    steps = sequence.sequence_steps.ordered
    assert_equal template1.id, steps.first.email_template_id
    assert_equal template2.id, steps.second.email_template_id
  end

  test "creating sequence with default timing pattern" do
    visit scout_path

    fill_in "message-input", with: "Create a 4-email nurture sequence for Default Contact Group"
    click_button "send-button"

    # Wait for AI questions and respond
    assert_text "sequence", wait: 10

    fill_in "message-input", with: "Lead Nurture Campaign, generate content with AI"
    click_button "send-button"

    sleep 2
    fill_in "message-input", with: "4 emails"
    click_button "send-button"

    sleep 2
    fill_in "message-input", with: "Use default timing"
    click_button "send-button"

    # Wait for completion
    assert_text "sequence created", wait: 30

    # Verify default timing pattern (0, 3, 6, 9 days)
    sequence = @entity.email_sequences.last
    steps = sequence.sequence_steps.ordered.to_a

    assert_equal 0, steps[0].delay_hours
    assert_equal 72, steps[1].delay_hours  # 3 days
    assert_equal 144, steps[2].delay_hours # 6 days
    assert_equal 216, steps[3].delay_hours # 9 days
  end

  # ============================================================================
  # EDGE CASE TESTS
  # ============================================================================

  test "handles missing contact group gracefully" do
    visit scout_path

    fill_in "message-input", with: "Create an email sequence"
    click_button "send-button"

    assert_text "sequence", wait: 10

    # Provide non-existent contact group
    fill_in "message-input", with: "For the NonExistent Group, generate 2 emails"
    click_button "send-button"

    # AI should handle this and either:
    # 1. Ask for clarification, or
    # 2. Show available groups, or
    # 3. Create with error message

    # Wait for response
    sleep 3

    # The system should not crash - verify we can still interact
    fill_in "message-input", with: "Actually, use Default Contact Group"
    click_button "send-button"

    # Should recover and continue
    assert_text "sequence", wait: 15
  end

  test "validates minimum email requirement" do
    visit scout_path

    fill_in "message-input", with: "Create a sequence with just 1 email for Default Contact Group"
    click_button "send-button"

    # Wait for processing
    sleep 3

    # AI should either:
    # 1. Ask to add more emails (minimum 2), or
    # 2. Auto-adjust to 2 emails, or
    # 3. Show validation error

    # Provide correction
    fill_in "message-input", with: "Make it 2 emails instead"
    click_button "send-button"

    assert_text "sequence", wait: 15
  end

  test "handles invalid delay timing gracefully" do
    visit scout_path

    fill_in "message-input", with: "Create a sequence"
    click_button "send-button"

    assert_text "sequence", wait: 10

    # Provide invalid timing
    fill_in "message-input", with: "For Default Contact Group, 3 emails with timing: -5 days, 200 days, 500 days"
    click_button "send-button"

    # Wait for AI to process
    sleep 5

    # System should handle invalid values and either auto-fix or ask for correction
    # The sequence should eventually be created with valid timing

    # Provide valid timing
    fill_in "message-input", with: "Use 3 days between emails"
    click_button "send-button"

    assert_text "sequence", wait: 15
  end

  test "partial information provided - AI asks for missing data" do
    visit scout_path

    # Provide minimal information
    fill_in "message-input", with: "Create an email sequence called Flash Sale Promotion"
    click_button "send-button"

    # AI should ask about contact group
    assert_text "contact group", wait: 10

    fill_in "message-input", with: "Default Contact Group"
    click_button "send-button"

    # AI should ask about content strategy
    sleep 2
    fill_in "message-input", with: "Generate with AI"
    click_button "send-button"

    # AI should ask about number of emails
    sleep 2
    fill_in "message-input", with: "2 emails"
    click_button "send-button"

    # Should complete successfully
    assert_text "sequence created", wait: 30

    sequence = @entity.email_sequences.last
    assert sequence.name.include?("Flash Sale")
  end

  # ============================================================================
  # DATABASE VALIDATION TESTS
  # ============================================================================

  test "verifies entity scoping is correct" do
    visit scout_path

    fill_in "message-input", with: "Create a 2-email welcome sequence for Default Contact Group"
    click_button "send-button"

    # Complete the workflow
    sleep 3
    fill_in "message-input", with: "Generate content with AI, 3 days between emails"
    click_button "send-button"

    assert_text "sequence created", wait: 30

    sequence = @entity.email_sequences.last

    # Verify entity scoping
    assert_equal @entity.id, sequence.entity_id, "Sequence should belong to current entity"

    sequence.sequence_steps.each do |step|
      assert_equal sequence.id, step.email_sequence_id, "Step should belong to sequence"
    end

    sequence.sequence_enrollments.each do |enrollment|
      assert_equal @entity.id, enrollment.entity_id, "Enrollment should belong to entity"
      assert_equal sequence.id, enrollment.email_sequence_id, "Enrollment should belong to sequence"
    end
  end

  test "verifies all contacts in group are enrolled" do
    contacts_count = @contact_group.contacts.count
    assert contacts_count > 0, "Should have contacts to test with"

    visit scout_path

    fill_in "message-input", with: "Create a 2-email sequence for Default Contact Group, generate content"
    click_button "send-button"

    # Complete workflow
    sleep 3
    fill_in "message-input", with: "default timing"
    click_button "send-button"

    assert_text "sequence created", wait: 30

    sequence = @entity.email_sequences.last

    # Verify enrollment count
    assert_equal contacts_count, sequence.sequence_enrollments.count,
                 "All contacts should be enrolled"

    # Verify each contact is enrolled once
    @contact_group.contacts.each do |contact|
      enrollment = sequence.sequence_enrollments.find_by(contact: contact)
      assert_not_nil enrollment, "Contact #{contact.id} should be enrolled"
    end
  end

  test "verifies sequence metadata is stored correctly" do
    visit scout_path

    fill_in "message-input", with: "Create a 3-email onboarding sequence for Default Contact Group with AI content"
    click_button "send-button"

    # Complete workflow
    sleep 3
    fill_in "message-input", with: "Tag it with onboarding and welcome"
    click_button "send-button"

    sleep 2
    fill_in "message-input", with: "3 day spacing"
    click_button "send-button"

    assert_text "sequence created", wait: 30

    sequence = @entity.email_sequences.last

    # Verify basic attributes
    assert_equal "draft", sequence.status
    assert_not_nil sequence.name
    assert_not_nil sequence.goal
    assert sequence.metadata.is_a?(Hash), "Metadata should be a hash"
  end

  # ============================================================================
  # VALIDATION PHASE TESTS
  # ============================================================================

  test "validation ensures minimum steps requirement" do
    # This test ensures the validation phase catches sequences with < 2 steps
    visit scout_path

    fill_in "message-input", with: "Create minimal sequence for Default Contact Group"
    click_button "send-button"

    sleep 3
    fill_in "message-input", with: "Just 1 email with AI content"
    click_button "send-button"

    # Validation should fail or AI should auto-fix to minimum 2 emails
    # Wait for completion or fix
    sleep 10

    # If sequence was created, it should have at least 2 steps
    sequence = @entity.email_sequences.last
    if sequence
      assert sequence.sequence_steps.count >= 2, "Validation should ensure minimum 2 steps"
    end
  end

  test "validation ensures all steps have content" do
    visit scout_path

    fill_in "message-input", with: "Create 2-email sequence for Default Contact Group, AI generated content"
    click_button "send-button"

    sleep 3
    fill_in "message-input", with: "default timing"
    click_button "send-button"

    assert_text "sequence created", wait: 30

    sequence = @entity.email_sequences.last

    # Validation phase should ensure all steps have content
    sequence.sequence_steps.each do |step|
      has_content = (step.subject.present? && step.body.present?) || step.email_template_id.present?
      assert has_content, "Step #{step.step_number} should have content after validation"
    end
  end

  test "validation checks delay values are within acceptable range" do
    visit scout_path

    fill_in "message-input", with: "Create 3-email sequence for Default Contact Group"
    click_button "send-button"

    sleep 3
    fill_in "message-input", with: "AI content, 7 days between emails"
    click_button "send-button"

    assert_text "sequence created", wait: 30

    sequence = @entity.email_sequences.last

    # Validation should ensure delays are reasonable (0 to 2160 hours = 90 days)
    sequence.sequence_steps.each do |step|
      assert step.delay_hours >= 0, "Delay should be >= 0"
      assert step.delay_hours <= 2160, "Delay should be <= 90 days (2160 hours)"
    end
  end

  # ============================================================================
  # WORKFLOW STATE TESTS
  # ============================================================================

  test "sequence is created in draft state" do
    visit scout_path

    fill_in "message-input", with: "Create 2-email test sequence for Default Contact Group, AI content, default timing"
    click_button "send-button"

    assert_text "sequence created", wait: 30

    sequence = @entity.email_sequences.last
    assert_equal "draft", sequence.status, "New sequences should be in draft status"
    assert_text "Draft", "UI should indicate draft status"
  end

  test "enrollments are created in pending state" do
    visit scout_path

    fill_in "message-input", with: "Create 2-email sequence for Default Contact Group, AI content"
    click_button "send-button"

    sleep 3
    click_button "send-button"  # Submit for default timing

    assert_text "sequence created", wait: 30

    sequence = @entity.email_sequences.last

    # All enrollments should be pending until sequence is activated
    sequence.sequence_enrollments.each do |enrollment|
      assert_equal "pending", enrollment.status, "Enrollments should be pending in draft sequence"
      assert_equal 0, enrollment.current_step_number, "Should start at step 0"
    end
  end

  test "success message includes key information" do
    visit scout_path

    fill_in "message-input", with: "Create 3-email welcome series for Default Contact Group, AI content, 3 days apart"
    click_button "send-button"

    assert_text "sequence created", wait: 30

    # Success message should include:
    # - Confirmation of creation
    # - Sequence name
    # - Number of emails
    # - Draft status
    # - Next steps

    assert_text "3", "Should mention number of emails"
    assert_text "Draft", "Should mention draft status"
    assert_text "review", "Should mention next steps"
  end

  private

  def scout_path
    "/scout"
  end
end
