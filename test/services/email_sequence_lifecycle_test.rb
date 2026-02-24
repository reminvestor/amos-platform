# frozen_string_literal: true

require "test_helper"

class EmailSequenceLifecycleTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
    @group = ContactGroup.create!(
      name: "Lifecycle Test Group",
      entity: @entity,
      user: @user
    )
  end

  teardown do
    # Clean up in FK-safe order
    seq_ids = EmailSequence.where(entity: @entity, contact_group: @group).pluck(:id)
    if seq_ids.any?
      SequenceEmailDelivery.where(email_sequence_id: seq_ids).delete_all
      SequenceEnrollment.where(email_sequence_id: seq_ids).delete_all
      template_ids = SequenceStep.where(email_sequence_id: seq_ids).pluck(:email_template_id).compact
      SequenceStep.where(email_sequence_id: seq_ids).delete_all
      EmailSequence.where(id: seq_ids).delete_all
      EmailTemplate.where(id: template_ids, entity: @entity).delete_all if template_ids.any?
    end
    CampaignGroup.where(contact_group_id: @group.id).delete_all
    ActiveRecord::Base.connection.execute(
      "DELETE FROM contact_groups_contacts WHERE contact_group_id = #{@group.id}"
    )
    @group.destroy
  end

  # ═══════════════════════════════════════════════════════════════
  # CreateObjectTool — email sequence duplicate name handling
  # ═══════════════════════════════════════════════════════════════

  test "create_email_sequence returns existing sequence when name matches" do
    existing = EmailSequence.create!(
      name: "Onboarding Welcome",
      entity: @entity,
      created_by: @user,
      contact_group: @group,
      status: "active"
    )

    tool = Tools::CreateObjectTool.new(user: @user, entity: @entity, context: {})
    result = tool.execute({
      "object_type" => "email_sequences",
      "data" => { "name" => "Onboarding Welcome", "contact_group_id" => @group.id }
    })

    assert_equal existing.id, result[:id]
    # Should reset to draft
    existing.reload
    assert_equal "draft", existing.status
  end

  test "create_email_sequence creates new when name does not exist" do
    tool = Tools::CreateObjectTool.new(user: @user, entity: @entity, context: {})
    result = tool.execute({
      "object_type" => "email_sequences",
      "data" => { "name" => "Brand New Sequence", "contact_group_id" => @group.id }
    })

    assert result[:id].present?
    seq = EmailSequence.find(result[:id])
    assert_equal "Brand New Sequence", seq.name
    assert_equal "draft", seq.status
  end

  # ═══════════════════════════════════════════════════════════════
  # CreateObjectTool — sequence step duplicate step_number handling
  # ═══════════════════════════════════════════════════════════════

  test "create_sequence_step updates existing when step_number conflicts" do
    seq = EmailSequence.create!(
      name: "Step Conflict Test",
      entity: @entity,
      created_by: @user,
      contact_group: @group
    )
    template = EmailTemplate.create!(
      name: "Step 1 Template",
      subject: "Original Subject",
      body: "<p>Original</p>",
      entity: @entity,
      user: @user
    )
    existing_step = SequenceStep.create!(
      email_sequence: seq,
      email_template: template,
      step_number: 1,
      delay_hours: 0
    )

    tool = Tools::CreateObjectTool.new(user: @user, entity: @entity, context: {})
    result = tool.execute({
      "object_type" => "sequence_steps",
      "data" => {
        "email_sequence_id" => seq.id,
        "step_number" => 1,
        "delay_hours" => 24,
        "subject" => "Updated Subject",
        "body" => "<p>Updated</p>"
      }
    })

    assert_equal existing_step.id, result[:id]
    existing_step.reload
    assert_equal 24, existing_step.delay_hours
  end

  test "create_sequence_step auto-assigns step_number when missing" do
    seq = EmailSequence.create!(
      name: "Auto Step Number Test",
      entity: @entity,
      created_by: @user,
      contact_group: @group
    )
    SequenceStep.create!(
      email_sequence: seq,
      step_number: 1,
      delay_hours: 0,
      subject: "Step 1",
      body: "<p>Step 1</p>"
    )

    tool = Tools::CreateObjectTool.new(user: @user, entity: @entity, context: {})
    result = tool.execute({
      "object_type" => "sequence_steps",
      "data" => {
        "email_sequence_id" => seq.id,
        "delay_hours" => 48,
        "subject" => "Step 2",
        "body" => "<p>Step 2</p>"
      }
    })

    step = SequenceStep.find(result[:id])
    assert_equal 2, step.step_number
  end

  # ═══════════════════════════════════════════════════════════════
  # UpdateObjectTool — invalid attribute filtering
  # ═══════════════════════════════════════════════════════════════

  test "update_email_sequence filters out invalid attributes like emails" do
    seq = EmailSequence.create!(
      name: "Filter Test Sequence",
      entity: @entity,
      created_by: @user,
      contact_group: @group
    )

    tool = Tools::UpdateObjectTool.new(user: @user, entity: @entity, context: {})
    result = tool.execute({
      "object_type" => "email_sequence",
      "id" => seq.id,
      "data" => {
        "name" => "Renamed Sequence",
        "emails" => [{ "subject" => "Test", "body" => "Body" }],
        "steps" => [{ "step_number" => 1 }],
        "nonexistent_field" => "should be ignored"
      }
    })

    assert_not result.is_a?(Hash) && result[:error]
    seq.reload
    assert_equal "Renamed Sequence", seq.name
  end

  test "update_sequence_step filters out invalid attributes" do
    seq = EmailSequence.create!(
      name: "Step Filter Test",
      entity: @entity,
      created_by: @user,
      contact_group: @group
    )
    step = SequenceStep.create!(
      email_sequence: seq,
      step_number: 1,
      delay_hours: 0,
      subject: "Original",
      body: "<p>Original</p>"
    )

    tool = Tools::UpdateObjectTool.new(user: @user, entity: @entity, context: {})
    result = tool.execute({
      "object_type" => "sequence_step",
      "id" => step.id,
      "data" => {
        "delay_hours" => 48,
        "bogus_field" => "should be filtered",
        "content" => "also not a real column"
      }
    })

    step.reload
    assert_equal 48, step.delay_hours
  end

  test "update_email_template filters out invalid attributes like from_name" do
    template = EmailTemplate.create!(
      name: "Template Filter Test",
      subject: "Test Subject",
      body: "<p>Test</p>",
      entity: @entity,
      user: @user
    )

    tool = Tools::UpdateObjectTool.new(user: @user, entity: @entity, context: {})
    result = tool.execute({
      "object_type" => "email_template",
      "id" => template.id,
      "data" => {
        "subject" => "Updated Subject",
        "from_name" => "Should be filtered",
        "from_email" => "also@filtered.com"
      }
    })

    template.reload
    assert_equal "Updated Subject", template.subject
  end

  # ═══════════════════════════════════════════════════════════════
  # PlatformCreateTool — one-call email sequence builder
  # ═══════════════════════════════════════════════════════════════

  test "build_email_sequence creates sequence with steps in one call" do
    tool = V3::Tools::PlatformCreateTool.new(user: @user, entity: @entity, context: {})
    result = tool.execute({
      "type" => "email_sequence",
      "data" => {
        "name" => "One Call Builder Test",
        "contact_group_id" => @group.id,
        "emails" => [
          { "subject" => "Welcome!", "body" => "<h1>Hi</h1>", "delay_hours" => 0 },
          { "subject" => "Follow Up", "body" => "<h1>Hey</h1>", "delay_hours" => 48 },
          { "subject" => "Final", "body" => "<h1>Last</h1>", "delay_hours" => 120 }
        ]
      }
    })

    assert result[:id].present?
    assert_equal 3, result[:steps_created]

    seq = EmailSequence.find(result[:id])
    assert_equal 3, seq.sequence_steps.count
    assert_equal [0, 48, 120], seq.sequence_steps.ordered.pluck(:delay_hours)
  end

  test "build_email_sequence activates when activate flag is true" do
    tool = V3::Tools::PlatformCreateTool.new(user: @user, entity: @entity, context: {})
    result = tool.execute({
      "type" => "email_sequence",
      "data" => {
        "name" => "Auto Activate Test",
        "contact_group_id" => @group.id,
        "activate" => true,
        "emails" => [
          { "subject" => "Step 1", "body" => "<p>Content</p>", "delay_hours" => 0 }
        ]
      }
    })

    seq = EmailSequence.find(result[:id])
    assert_equal "active", seq.status
  end

  # ═══════════════════════════════════════════════════════════════
  # Idempotency — re-running same create should not fail
  # ═══════════════════════════════════════════════════════════════

  test "creating email sequence twice with same name does not raise" do
    tool = V3::Tools::PlatformCreateTool.new(user: @user, entity: @entity, context: {})

    result1 = tool.execute({
      "type" => "email_sequence",
      "data" => {
        "name" => "Idempotent Sequence",
        "contact_group_id" => @group.id,
        "emails" => [
          { "subject" => "Welcome", "body" => "<p>Hi</p>", "delay_hours" => 0 }
        ]
      }
    })

    result2 = tool.execute({
      "type" => "email_sequence",
      "data" => {
        "name" => "Idempotent Sequence",
        "contact_group_id" => @group.id,
        "emails" => [
          { "subject" => "Welcome v2", "body" => "<p>Hi again</p>", "delay_hours" => 0 }
        ]
      }
    })

    assert result1[:id].present?
    assert result2[:id].present?
    # Should reuse the same sequence, not create a duplicate
    assert_equal result1[:id], result2[:id]
  end
end
