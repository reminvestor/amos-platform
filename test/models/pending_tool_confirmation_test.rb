# frozen_string_literal: true

require "test_helper"

class PendingToolConfirmationTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @user = users(:one)
  end

  test "creates with required fields" do
    confirmation = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      tool_args: { object_type: "contact" },
      action_description: "Create new contact"
    )

    assert confirmation.persisted?
    assert confirmation.confirmation_id.present?
    assert_equal "pending", confirmation.status
    assert confirmation.expires_at.present?
    assert confirmation.expires_at > Time.current
  end

  test "confirmation_id is unique" do
    confirmation1 = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      confirmation_id: "unique-id-123"
    )

    confirmation2 = PendingToolConfirmation.new(
      entity: @entity,
      user: @user,
      tool_name: "update_object",
      confirmation_id: "unique-id-123"
    )

    assert_not confirmation2.valid?
    assert confirmation2.errors[:confirmation_id].present?
  end

  test "confirms changes status" do
    confirmation = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "create_object"
    )

    confirmation.confirm!

    assert_equal "confirmed", confirmation.status
    assert confirmation.resolved_at.present?
  end

  test "denies changes status" do
    confirmation = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "create_object"
    )

    confirmation.deny!

    assert_equal "denied", confirmation.status
    assert confirmation.resolved_at.present?
  end

  test "expired? returns true when past expiration" do
    confirmation = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      expires_at: 1.minute.ago
    )

    assert confirmation.expired?
    assert_not confirmation.pending?
  end

  test "pending scope excludes non-pending" do
    pending = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "create_object"
    )

    confirmed = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "update_object",
      status: "confirmed"
    )

    results = PendingToolConfirmation.pending
    assert_includes results, pending
    assert_not_includes results, confirmed
  end

  test "not_expired scope excludes expired" do
    valid = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      expires_at: 10.minutes.from_now
    )

    expired = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "update_object",
      expires_at: 1.minute.ago
    )

    results = PendingToolConfirmation.not_expired
    assert_includes results, valid
    assert_not_includes results, expired
  end

  test "for_session filters by session_id" do
    session1 = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      session_id: "session-123"
    )

    session2 = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "update_object",
      session_id: "session-456"
    )

    results = PendingToolConfirmation.for_session("session-123")
    assert_includes results, session1
    assert_not_includes results, session2
  end

  test "active scope combines pending and not_expired" do
    active = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      status: "pending",
      expires_at: 10.minutes.from_now
    )

    expired_pending = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "update_object",
      status: "pending",
      expires_at: 1.minute.ago
    )

    confirmed = PendingToolConfirmation.create!(
      entity: @entity,
      user: @user,
      tool_name: "delete_object",
      status: "confirmed",
      expires_at: 10.minutes.from_now
    )

    results = PendingToolConfirmation.active
    assert_includes results, active
    assert_not_includes results, expired_pending
    assert_not_includes results, confirmed
  end

  test "validates status inclusion" do
    confirmation = PendingToolConfirmation.new(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      status: "invalid_status"
    )

    assert_not confirmation.valid?
    assert confirmation.errors[:status].present?
  end
end
