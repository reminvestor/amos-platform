# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class CrossPlatformWorkflow
        GROUP_NAME = "New This Week"
        CAMPAIGN_PATTERN = "%new this week%"

        TEST_CONTACTS = [
          { first_name: "Nadia", last_name: "Kim", email: "nadia@startuplab.io" },
          { first_name: "Carlos", last_name: "Vega", email: "carlos@scaleup.co" },
          { first_name: "Priya", last_name: "Sharma", email: "priya@growthops.dev" },
          { first_name: "Old", last_name: "Contact", email: "old@legacy.com" },
        ].freeze

        ALL_BENCHMARK_EMAILS = (
          TEST_CONTACTS.map { |c| c[:email] } +
          %w[
            dana@techforward.io raj@cloudnative.dev erin@designstack.co
            john@acme.com sarah@techstart.io mike@growthco.com
            lisa@designlab.co tom@buildright.com
            alice@test.com bob@invalid charlie@test.com
          ]
        ).freeze

        def self.cleanup!(entity)
          Campaign.where(entity: entity).where("name ILIKE ?", CAMPAIGN_PATTERN).find_each do |c|
            c.campaign_groups.delete_all
            c.email_deliveries.delete_all
            c.destroy
          rescue => e
            Rails.logger.debug "[BenchmarkCleanup] Campaign #{c.id}: #{e.message}"
          end

          ContactGroup.where(entity: entity, name: GROUP_NAME).find_each do |g|
            g.contacts.clear
            g.email_sequences.find_each do |seq|
              seq.sequence_enrollments.delete_all
              seq.sequence_steps.delete_all
              seq.destroy
            rescue => e
              Rails.logger.debug "[BenchmarkCleanup] EmailSequence #{seq.id}: #{e.message}"
            end
            CampaignGroup.where(contact_group_id: g.id).delete_all
            g.destroy
          rescue => e
            Rails.logger.debug "[BenchmarkCleanup] ContactGroup #{g.id}: #{e.message}"
          end

          # Clean ALL benchmark-related contacts AND any contacts created in the
          # last 8 days so the "last 7 days" query only returns our seeded data
          contacts_to_remove = Contact.where(entity: entity).where(
            "email IN (?) OR created_at > ?", ALL_BENCHMARK_EMAILS, 8.days.ago
          )
          contacts_to_remove.find_each do |c|
            c.sequence_enrollments.delete_all
            ActiveRecord::Base.connection.execute(
              "DELETE FROM contact_groups_contacts WHERE contact_id = #{c.id}"
            )
            c.destroy
          rescue => e
            Rails.logger.debug "[BenchmarkCleanup] Contact #{c.id}: #{e.message}"
          end
        rescue => e
          Rails.logger.warn "[BenchmarkCleanup] cross_platform_workflow cleanup failed: #{e.message}"
        end

        def self.setup_contacts!(entity, user)
          recent = TEST_CONTACTS.first(3)
          recent.each do |attrs|
            Contact.where(entity: entity, email: attrs[:email]).first_or_create!(
              entity: entity, user: user, **attrs
            )
          end

          old_attrs = TEST_CONTACTS.last
          old_contact = Contact.where(entity: entity, email: old_attrs[:email]).first_or_create!(
            entity: entity, user: user, **old_attrs
          )
          old_contact.update_column(:created_at, 30.days.ago)
        end

        def self.build
          Scenario.new(
            id: :cross_platform_workflow,
            level: :L3,
            category: :data_analysis,
            name: "Data-driven workflow: query, group, and campaign from existing contacts",
            description: "Tests end-to-end orchestration starting from existing data. " \
                         "The AI must query contacts, filter by recency, create a group, " \
                         "build an email, and launch a campaign — all chained together. " \
                         "4 contacts are seeded: 3 recent (this week), 1 old (30 days ago). " \
                         "The AI should correctly filter and only include the 3 recent ones.",
            tags: [:core],
            setup: ->(entity:, user:) {
              CrossPlatformWorkflow.cleanup!(entity)
              CrossPlatformWorkflow.setup_contacts!(entity, user)
            },
            teardown: ->(entity:, user:) {
              CrossPlatformWorkflow.cleanup!(entity)
            },
            messages: [
              "Find my contacts that were added in the last 7 days, create a group called " \
              "'New This Week' with just those recent contacts, write a welcome email for them, " \
              "and set up a campaign targeting that group.",
            ],
            assertions: [
              { type: :tool_called, tool_name: "platform_query", min_times: 1 },
              { type: :tool_called, tool_name: "platform_create", min_times: 2 },
              { type: :record_exists, model: "ContactGroup", conditions: {} },
              { type: :no_errors },
              { type: :conversation_completed },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate the data-driven cross-platform workflow:
              1. DATA FILTERING (0-20): Did the AI correctly filter contacts?
                 - Queried contacts and identified which are recent (last 7 days)
                 - Included the 3 recent contacts (Nadia, Carlos, Priya)
                 - Excluded the old contact (Old Contact, created 30 days ago)
                 - If all contacts were included without filtering, deduct heavily
              2. GROUP CREATION (0-15): Was the group set up correctly?
                 - Created group named 'New This Week'
                 - Added only the filtered recent contacts to the group
                 - Didn't create duplicate groups
              3. CAMPAIGN QUALITY (0-15): Is the campaign well-built?
                 - Created an email template with personalization
                 - Campaign is linked to the 'New This Week' group
                 - Subject line and content are welcoming/appropriate
              4. ORCHESTRATION (0-15): Was the multi-step flow executed cleanly?
                 - Steps executed in logical order: query → filter → group → template → campaign
                 - Context maintained across steps (IDs passed correctly)
                 - No unnecessary tool calls or redundant queries
            RUBRIC
            timeout_seconds: 240
          )
        end
      end
    end
  end
end
