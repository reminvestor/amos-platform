# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class EmailSequenceFullLifecycle
        GROUP_NAME = "Onboarding Customers"
        SEQUENCE_NAME_PATTERN = "%onboarding%"

        TEST_CONTACTS = [
          { first_name: "Dana", last_name: "Rivera", email: "dana@techforward.io" },
          { first_name: "Raj", last_name: "Patel", email: "raj@cloudnative.dev" },
          { first_name: "Erin", last_name: "Cho", email: "erin@designstack.co" },
        ].freeze

        def self.cleanup!(entity)
          # Delete sequences first (they reference the group via FK)
          EmailSequence.where(entity: entity).where("name ILIKE ?", SEQUENCE_NAME_PATTERN).find_each do |seq|
            seq.sequence_enrollments.delete_all
            seq.sequence_steps.each { |s| s.update_columns(email_template_id: nil) }
            seq.sequence_steps.delete_all
            seq.destroy!
          rescue => e
            Rails.logger.debug "[BenchmarkCleanup] EmailSequence #{seq.id}: #{e.message}"
          end

          # Also clean any sequences linked to our group
          ContactGroup.where(entity: entity, name: GROUP_NAME).find_each do |g|
            g.email_sequences.find_each do |seq|
              seq.sequence_enrollments.delete_all
              seq.sequence_steps.delete_all
              seq.destroy!
            rescue => e
              Rails.logger.debug "[BenchmarkCleanup] EmailSequence #{seq.id}: #{e.message}"
            end
            g.contacts.clear
            CampaignGroup.where(contact_group_id: g.id).delete_all
            g.destroy!
          rescue => e
            Rails.logger.debug "[BenchmarkCleanup] ContactGroup #{g.id}: #{e.message}"
          end

          test_emails = TEST_CONTACTS.map { |c| c[:email] }
          Contact.where(entity: entity, email: test_emails).find_each do |c|
            c.sequence_enrollments.delete_all
            ActiveRecord::Base.connection.execute(
              "DELETE FROM contact_groups_contacts WHERE contact_id = #{c.id}"
            )
            c.destroy
          rescue => e
            Rails.logger.debug "[BenchmarkCleanup] Contact #{c.id}: #{e.message}"
          end
        rescue => e
          Rails.logger.warn "[BenchmarkCleanup] email_sequence_full_lifecycle cleanup failed: #{e.message}"
        end

        def self.setup_contacts!(entity, user)
          group = ContactGroup.find_or_create_by!(entity: entity, user: user, name: GROUP_NAME)
          group.contacts.clear
          TEST_CONTACTS.each do |attrs|
            contact = Contact.where(entity: entity, email: attrs[:email]).first_or_create!(
              entity: entity, user: user, **attrs
            )
            group.contacts << contact unless group.contacts.include?(contact)
          end
          group
        end

        def self.build
          Scenario.new(
            id: :email_sequence_full_lifecycle,
            level: :L3,
            category: :content_creation,
            name: "Full lifecycle: email sequence with enrollment and activation",
            description: "Tests the complete automation pipeline beyond just creation. " \
                         "The AI must find an existing contact group, create a multi-step " \
                         "email sequence with correct timing, and activate it. " \
                         "Exercises platform_query (find group), platform_create (sequence + steps), " \
                         "and state management (draft → active).",
            tags: [:core],
            setup: ->(entity:, user:) {
              EmailSequenceFullLifecycle.cleanup!(entity)
              EmailSequenceFullLifecycle.setup_contacts!(entity, user)
            },
            teardown: ->(entity:, user:) {
              EmailSequenceFullLifecycle.cleanup!(entity)
            },
            messages: [
              "I have a contact group called 'Onboarding Customers' with 3 people in it. " \
              "Create a 3-email onboarding sequence for them: first email immediately welcoming " \
              "them, second email 2 days later with a getting started guide, and third email " \
              "5 days later asking for feedback. Then activate the sequence so it starts sending.",
            ],
            assertions: [
              { type: :tool_called, tool_name: "platform_query", min_times: 1 },
              { type: :tool_called, tool_name: "platform_create", min_times: 1 },
              { type: :no_errors },
              { type: :conversation_completed },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate the full email sequence lifecycle:
              1. TASK_COMPLETION (0-25): Was the entire pipeline completed?
                 - Found the 'Onboarding Customers' group via platform_query
                 - Created email sequence linked to that group (contact_group_id)
                 - Created 3 steps with correct timing (0h, 48h, 120h)
                 - Sequence was activated (status: active, not left in draft)
                 - NOTE: The platform supports a one-call builder — passing an 'emails' array
                   in a single platform_create call auto-creates templates, steps, enrolls
                   contacts, and activates. This is the PREFERRED efficient approach.
              2. CONTENT_QUALITY (0-15): Are the emails well-crafted?
                 - Each email has a distinct purpose (welcome, guide, feedback)
                 - Subject lines are compelling
                 - Personalization tokens used (e.g., {{first_name}})
                 - Email content was provided in the tool call (not just described in chat)
              3. DATA_ACCURACY (0-15): Is the wiring correct?
                 - Sequence is linked to the correct contact group
                 - Step delays match what was requested (0, 48h, 120h)
                 - Step ordering is correct (1, 2, 3)
                 - Tool result confirms records were created (steps_created > 0)
              4. EFFICIENCY (0-10): Was this done smoothly?
                 - Found the group without asking the user to look it up
                 - Didn't create duplicate groups or sequences
                 - Used one-call builder with emails array (most efficient)
                 - If the first call had no emails, retried correctly with the full array
            RUBRIC
            timeout_seconds: 240
          )
        end
      end
    end
  end
end
