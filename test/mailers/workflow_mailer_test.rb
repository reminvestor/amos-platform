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

    from = email.header["From"].to_s
    assert from.present?, "Should have a from address"
  end

  test "workflow_email sends from verified custom domain" do
    # Entity :one has a verified_email_domain fixture
    entity_with_domain = entities(:one)

    email = WorkflowMailer.workflow_email(
      to: "test@example.com",
      subject: "Test Custom Domain",
      body: "<p>Hello</p>",
      entity_id: entity_with_domain.id
    )

    from = email.header["From"].to_s
    assert_includes from, "nuvolanetworks.com",
      "Should send from entity's verified custom domain"
    assert_includes from, entity_with_domain.name,
      "Should include entity name in from header"
  end

  test "workflow_email uses platform default when no verified domain" do
    # Entity :two has help_domain with email_status: pending (not verified)
    entity_no_email = entities(:two)

    email = WorkflowMailer.workflow_email(
      to: "test@example.com",
      subject: "Test Default",
      body: "<p>Hello</p>",
      entity_id: entity_no_email.id
    )

    from = email.header["From"].to_s
    default_email = ENV['MAILER_SENDER'] || 'noreply@amoslabs.com'
    assert_includes from, default_email,
      "Should fall back to platform default"
  end

  test "workflow_email sets reply_to from entity" do
    entity_with_domain = entities(:one)

    email = WorkflowMailer.workflow_email(
      to: "test@example.com",
      subject: "Test",
      body: "Hi",
      entity_id: entity_with_domain.id
    )

    reply_to = email[:reply_to].to_s
    assert_includes reply_to, "nuvolanetworks.com",
      "Reply-to should use entity's verified domain"
  end
end
