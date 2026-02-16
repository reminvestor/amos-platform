# frozen_string_literal: true

require "test_helper"

class EntitySendingEmailTest < ActiveSupport::TestCase
  fixtures :entities, :users, :custom_domains

  setup do
    @entity_with_verified = entities(:one) # has verified_email_domain fixture
    @entity_no_verified = entities(:two)   # has help_domain (email_status: pending)
    @entity_default = entities(:default)   # has unverified_email_domain (email_status: pending)
  end

  # ─── sending_email_address ───

  test "sending_email_address uses verified custom domain when no from_email set" do
    assert_equal "hello@nuvolanetworks.com", @entity_with_verified.sending_email_address
  end

  test "sending_email_address uses explicit from_email when domain is SES-verified" do
    @entity_with_verified.update(from_email: "marketing@nuvolanetworks.com")
    assert_equal "marketing@nuvolanetworks.com", @entity_with_verified.sending_email_address
  end

  test "sending_email_address preserves from_email prefix when falling back to custom domain" do
    @entity_with_verified.update(from_email: "support@unverified-other.com")
    # from_email domain is not verified, so falls back to primary custom domain using the prefix
    assert_equal "support@nuvolanetworks.com", @entity_with_verified.sending_email_address
  end

  test "sending_email_address falls back to platform default when no verified custom domain" do
    result = @entity_no_verified.sending_email_address
    assert_equal(ENV['MAILER_SENDER'] || 'noreply@amoslabs.com', result)
  end

  test "sending_email_address falls back to platform default when custom domain email is pending" do
    result = @entity_default.sending_email_address
    assert_equal(ENV['MAILER_SENDER'] || 'noreply@amoslabs.com', result)
  end

  # ─── sending_display_name ───

  test "sending_display_name uses sender_name when set" do
    @entity_with_verified.update(sender_name: "Nuvola Marketing")
    assert_equal "Nuvola Marketing", @entity_with_verified.sending_display_name
  end

  test "sending_display_name falls back to entity name" do
    assert_equal "Test Entity One", @entity_with_verified.sending_display_name
  end

  test "sending_display_name falls back to AMOS when no name" do
    entity = Entity.new(name: nil)
    assert_equal "AMOS", entity.sending_display_name
  end

  # ─── sending_from_header ───

  test "sending_from_header formats display name and email" do
    @entity_with_verified.update(sender_name: "Nuvola Networks")
    assert_equal "Nuvola Networks <hello@nuvolanetworks.com>", @entity_with_verified.sending_from_header
  end

  test "sending_from_header uses entity name when no sender_name" do
    header = @entity_with_verified.sending_from_header
    assert_equal "Test Entity One <hello@nuvolanetworks.com>", header
  end

  test "sending_from_header uses platform default when no verified domain" do
    header = @entity_no_verified.sending_from_header
    default_email = ENV['MAILER_SENDER'] || 'noreply@amoslabs.com'
    assert_equal "Test Entity Two <#{default_email}>", header
  end

  # ─── sending_reply_to ───

  test "sending_reply_to uses explicit reply_to_email when set" do
    @entity_with_verified.update(reply_to_email: "support@nuvolanetworks.com")
    assert_equal "support@nuvolanetworks.com", @entity_with_verified.sending_reply_to
  end

  test "sending_reply_to falls back to sending_email_address" do
    assert_equal "hello@nuvolanetworks.com", @entity_with_verified.sending_reply_to
  end

  # ─── settings persistence ───

  test "from_email is stored in and retrieved from settings JSONB" do
    @entity_with_verified.update(from_email: "hello@nuvolanetworks.com")
    @entity_with_verified.reload
    assert_equal "hello@nuvolanetworks.com", @entity_with_verified.from_email
  end

  test "sender_name is stored in and retrieved from settings JSONB" do
    @entity_with_verified.update(sender_name: "Custom Name")
    @entity_with_verified.reload
    assert_equal "Custom Name", @entity_with_verified.sender_name
  end

  test "reply_to_email is stored in and retrieved from settings JSONB" do
    @entity_with_verified.update(reply_to_email: "replies@nuvolanetworks.com")
    @entity_with_verified.reload
    assert_equal "replies@nuvolanetworks.com", @entity_with_verified.reply_to_email
  end
end
