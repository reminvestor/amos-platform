# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class CampaignEditAndRetarget
        CAMPAIGN_NAME = "Spring Promotion 2026"
        GROUP_NAMES = ["VIP Customers", "Newsletter Subscribers"].freeze
        TEMPLATE_NAME = "Spring Promo Email"

        TEST_EMAILS = ((1..5).map { |i| "vip#{i}@benchtest.io" } +
                       (1..5).map { |i| "sub#{i}@benchtest.io" }).freeze

        def self.cleanup!(entity)
          conn = ActiveRecord::Base.connection

          campaign_ids = Campaign.where(entity: entity).where("name ILIKE ?", "%spring promo%").pluck(:id)
          if campaign_ids.any?
            CampaignGroup.where(campaign_id: campaign_ids).delete_all
            Campaign.where(id: campaign_ids).delete_all
          end

          group_ids = ContactGroup.where(entity: entity, name: GROUP_NAMES).pluck(:id)
          if group_ids.any?
            CampaignGroup.where(contact_group_id: group_ids).delete_all
            conn.execute("DELETE FROM contact_groups_contacts WHERE contact_group_id IN (#{group_ids.join(',')})") rescue nil
            ContactGroup.where(id: group_ids).delete_all
          end

          EmailTemplate.where(entity: entity).where("name ILIKE ?", "%spring promo%").delete_all

          contact_ids = Contact.where(entity: entity, email: TEST_EMAILS).pluck(:id)
          if contact_ids.any?
            conn.execute("DELETE FROM contact_groups_contacts WHERE contact_id IN (#{contact_ids.join(',')})") rescue nil
            Contact.where(id: contact_ids).delete_all
          end
        rescue => e
          Rails.logger.warn "[BenchmarkCleanup] campaign_edit_and_retarget cleanup failed: #{e.message}"
        end

        def self.setup!(entity, user)
          cleanup!(entity)

          vip_group = ContactGroup.create!(entity: entity, user: user, name: "VIP Customers")
          newsletter_group = ContactGroup.create!(entity: entity, user: user, name: "Newsletter Subscribers")

          3.times do |i|
            contact = Contact.create!(
              entity: entity, user: user,
              first_name: "VIP#{i + 1}", last_name: "Customer",
              email: "vip#{i + 1}@benchtest.io"
            )
            vip_group.contacts << contact
          end

          2.times do |i|
            contact = Contact.create!(
              entity: entity, user: user,
              first_name: "Sub#{i + 1}", last_name: "Reader",
              email: "sub#{i + 1}@benchtest.io"
            )
            newsletter_group.contacts << contact
          end

          template = EmailTemplate.create!(
            entity: entity, user: user,
            name: TEMPLATE_NAME,
            subject: "Spring Sale is Here",
            body: "<p>Hi {{first_name}}, our spring sale has started. Check out our deals.</p>"
          )

          campaign = Campaign.create!(
            entity: entity, user: user,
            name: CAMPAIGN_NAME,
            email_template: template,
            status: "draft"
          )
          campaign.contact_groups << vip_group

          { campaign: campaign, template: template, vip_group: vip_group, newsletter_group: newsletter_group }
        end

        def self.build
          Scenario.new(
            id: :campaign_edit_and_retarget,
            level: :L3,
            category: :iterative_editing,
            name: "Edit campaign copy and adjust targeting",
            description: "Tests the common workflow of reviewing a campaign and then " \
                         "making edits to the copy and targeting before sending. " \
                         "A draft campaign exists targeting VIP Customers. The user " \
                         "asks to review it, then improve the subject line and expand " \
                         "targeting to also include Newsletter Subscribers.",
            tags: [:core],
            setup: ->(entity:, user:) {
              CampaignEditAndRetarget.setup!(entity, user)
            },
            teardown: ->(entity:, user:) {
              CampaignEditAndRetarget.cleanup!(entity)
            },
            messages: [
              "Show me the 'Spring Promotion 2026' campaign — what's the subject line, " \
              "which groups is it targeting, and what's the email content?",

              "Let's improve this before sending. Change the subject line to " \
              "'🌸 Spring Into Savings — 30% Off This Week Only!' and also " \
              "add the 'Newsletter Subscribers' group to the targeting so we reach more people.",
            ],
            assertions: [
              { type: :tool_called, tool_name: "platform_query", min_times: 1 },
              { type: :tool_called, tool_name: "platform_update", min_times: 1 },
              { type: :no_errors },
              { type: :conversation_completed },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate the AI's ability to review and edit an existing campaign:

              1. CAMPAIGN_REVIEW (0-15): Did Turn 1 accurately present the campaign?
                 - Found the 'Spring Promotion 2026' campaign
                 - Showed the current subject line ('Spring Sale is Here')
                 - Identified the targeting group (VIP Customers, 3 contacts)
                 - Showed the email body content
                 - Mentioned it's in draft status

              2. SUBJECT_LINE_UPDATE (0-20): Was the subject line changed correctly?
                 - Used platform_update on the email template
                 - New subject is the requested one (with emoji and urgency)
                 - Did NOT create a new template — updated the existing one
                 - Confirmed the change to the user

              3. TARGETING_EXPANSION (0-20): Was the Newsletter Subscribers group added?
                 - Used platform_update on the campaign to add the group
                 - Used add_contact_group_ids (append) NOT contact_group_ids (replace)
                 - VIP Customers group was NOT removed (both groups targeted now)
                 - Confirmed the expanded reach (3 + 2 = 5 contacts)

              4. ACCURACY (0-5): Were the edits precise?
                 - Only changed what was requested
                 - Didn't modify the email body content
                 - Didn't change the campaign status
                 - Campaign remains in draft (wasn't accidentally sent)

              5. COMMUNICATION (0-5): Was the edit process clear?
                 - Summarized what was changed
                 - Confirmed the new targeting (both groups)
                 - Offered next steps (ready to send, preview, etc.)
            RUBRIC
            timeout_seconds: 120
          )
        end
      end
    end
  end
end
