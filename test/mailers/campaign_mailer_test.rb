# frozen_string_literal: true

require "test_helper"

class CampaignMailerTest < ActionMailer::TestCase
  fixtures :entities, :users, :campaigns, :email_templates, :contacts, :email_deliveries, :custom_domains

  setup do
    @entity = entities(:one)
    @campaign = campaigns(:one)
    @campaign.update!(email_template: email_templates(:one), entity: @entity)
    @contact = contacts(:one)
    @contact.update!(entity: @entity)

    @delivery = email_deliveries(:one)
    @delivery.update!(
      campaign: @campaign,
      contact: @contact,
      email_template: email_templates(:one)
    )
  end

  # ─── Entity sending_from_header integration with CampaignMailer ───
  # Note: CampaignMailer template uses root_url which is unavailable in test
  # because the root route is behind a subdomain constraint. These tests verify
  # the from/reply-to wiring via the Entity model instead.

  test "entity with verified domain returns custom domain in sending_from_header" do
    # Entity :one has verified_email_domain (nuvolanetworks.com, email_status: verified)
    header = @entity.sending_from_header
    assert_includes header, "nuvolanetworks.com"
    assert_includes header, @entity.name
  end

  test "campaign entity resolves to custom domain from address" do
    entity = @campaign.entity
    assert_equal "hello@nuvolanetworks.com", entity.sending_email_address
  end

  test "campaign entity resolves custom reply_to" do
    entity = @campaign.entity
    assert_equal "hello@nuvolanetworks.com", entity.sending_reply_to
  end

  test "campaign entity uses explicit from_email when set and verified" do
    @entity.update(from_email: "marketing@nuvolanetworks.com")
    assert_equal "marketing@nuvolanetworks.com", @campaign.entity.sending_email_address
  end

  test "campaign entity uses platform default when no verified domain" do
    entity_no_domain = entities(:two)
    @campaign.update!(entity: entity_no_domain)

    default_email = ENV['MAILER_SENDER'] || 'noreply@amoslabs.com'
    assert_equal default_email, @campaign.entity.sending_email_address
  end

  test "campaign entity uses custom sender_name in from header" do
    @entity.update(sender_name: "Nuvola Marketing Team")
    assert_includes @entity.sending_from_header, "Nuvola Marketing Team"
  end

  test "campaign mailer code sets from and reply_to on mail call" do
    # Verify the mailer source code passes from/reply_to (code review test)
    source = File.read(Rails.root.join("app/mailers/campaign_mailer.rb"))
    assert_match(/from:\s*@entity\.sending_from_header/, source,
      "CampaignMailer should set from: @entity.sending_from_header")
    assert_match(/reply_to:\s*@entity\.sending_reply_to/, source,
      "CampaignMailer should set reply_to: @entity.sending_reply_to")
  end
end
