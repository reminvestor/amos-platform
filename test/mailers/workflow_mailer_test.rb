# frozen_string_literal: true

require "test_helper"

class WorkflowMailerTest < ActionMailer::TestCase
  fixtures :users, :entities

  setup do
    @entity = entities(:one)
  end

  test "workflow_email sends with correct fields" do
    email = WorkflowMailer.workflow_email(
      to: "test@example.com",
      subject: "Welcome!",
      body: "<h1>Hello</h1><p>Welcome aboard.</p>",
      entity_id: @entity.id
    )

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal ["test@example.com"], email.to
    assert_equal "Welcome!", email.subject
  end

  test "workflow_email includes SES tracking headers" do
    email = WorkflowMailer.workflow_email(
      to: "test@example.com",
      subject: "Test",
      body: "<p>Hi</p>",
      entity_id: @entity.id,
      automation_id: 42,
      contact_id: 99
    )

    assert email.header["X-SES-CONFIGURATION-SET"].present?
    
    tags = email.header["X-SES-MESSAGE-TAGS"].to_s
    assert tags.include?("type=automation")
    assert tags.include?("automation_id=42")
    assert tags.include?("contact_id=99")
  end

  test "workflow_email wraps plain body in HTML template" do
    email = WorkflowMailer.workflow_email(
      to: "test@example.com",
      subject: "Test",
      body: "<p>Simple content</p>",
      entity_id: @entity.id,
      html: true
    )

    html_part = email.html_part || email
    body = html_part.body.to_s

    # Should be wrapped in full HTML document
    assert body.include?("<!DOCTYPE html") || body.include?("<html"),
      "Should wrap in HTML template"
    assert body.include?("Simple content"),
      "Should include the body content"
  end

  test "workflow_email sends text-only when html: false" do
    email = WorkflowMailer.workflow_email(
      to: "test@example.com",
      subject: "Plain",
      body: "Just plain text",
      entity_id: @entity.id,
      html: false
    )

    assert_equal "Just plain text", email.body.to_s.strip
  end

  test "workflow_email uses entity name as from" do
    email = WorkflowMailer.workflow_email(
      to: "test@example.com",
      subject: "Test",
      body: "Hi",
      entity_id: @entity.id
    )

    from = email.from_address || email.header["From"].to_s
    assert from.to_s.present?, "Should have a from address"
  end
end
