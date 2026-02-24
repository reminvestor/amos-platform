# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class EmailSequenceRefinement
        SEQUENCE_NAME = "Product Launch Series"

        GROUP_NAME = "Launch Subscribers"

        INITIAL_STEPS = [
          { subject: "Welcome to Our Product Launch", body: "<p>Hi {{first_name}}, thanks for signing up!</p>", delay_hours: 0 },
          { subject: "Getting Started Guide", body: "<p>Hi {{first_name}}, here is how to get started with our product.</p>", delay_hours: 48 },
          { subject: "Tips and Tricks", body: "<p>Hi {{first_name}}, here are some tips to get the most value.</p>", delay_hours: 120 },
        ].freeze

        def self.cleanup!(entity)
          conn = ActiveRecord::Base.connection

          seq_ids = EmailSequence.where(entity: entity).where("name ILIKE ?", "%#{SEQUENCE_NAME}%").pluck(:id)

          if seq_ids.any?
            template_ids = SequenceStep.where(email_sequence_id: seq_ids).pluck(:email_template_id).compact
            SequenceEmailDelivery.where(email_sequence_id: seq_ids).delete_all
            SequenceEnrollment.where(email_sequence_id: seq_ids).delete_all
            SequenceStep.where(email_sequence_id: seq_ids).update_all(email_template_id: nil)
            SequenceStep.where(email_sequence_id: seq_ids).delete_all
            EmailSequence.where(id: seq_ids).delete_all
            EmailTemplate.where(id: template_ids, entity: entity).delete_all if template_ids.any?
          end

          group_ids = ContactGroup.where(entity: entity, name: GROUP_NAME).pluck(:id)
          if group_ids.any?
            CampaignGroup.where(contact_group_id: group_ids).delete_all
            conn.execute("DELETE FROM contact_groups_contacts WHERE contact_group_id IN (#{group_ids.join(',')})") rescue nil
            ContactGroup.where(id: group_ids).delete_all
          end
        rescue => e
          Rails.logger.warn "[BenchmarkCleanup] email_sequence_refinement cleanup failed: #{e.message}"
        end

        def self.setup!(entity, user)
          cleanup!(entity)

          group = ContactGroup.find_or_create_by!(entity: entity, user: user, name: GROUP_NAME)

          sequence = EmailSequence.create!(
            entity: entity,
            created_by: user,
            contact_group: group,
            name: SEQUENCE_NAME,
            goal: "Onboard new users after product launch signup",
            status: "draft"
          )

          INITIAL_STEPS.each_with_index do |step_data, idx|
            template = EmailTemplate.create!(
              entity: entity,
              user: user,
              name: "#{SEQUENCE_NAME} - Email #{idx + 1}",
              subject: step_data[:subject],
              body: step_data[:body]
            )

            SequenceStep.create!(
              email_sequence: sequence,
              email_template: template,
              step_number: idx + 1,
              delay_hours: step_data[:delay_hours]
            )
          end

          sequence
        end

        def self.build
          Scenario.new(
            id: :email_sequence_refinement,
            level: :L3,
            category: :iterative_editing,
            name: "Refine an existing email sequence",
            description: "Tests the iterative editing workflow for email sequences. " \
                         "A 3-step sequence already exists. The user reviews it, then asks " \
                         "to improve a subject line, adjust timing, and strengthen the CTA " \
                         "in the final email. Exercises platform_query, platform_update " \
                         "on both email templates and sequence steps.",
            tags: [:core],
            setup: ->(entity:, user:) {
              EmailSequenceRefinement.setup!(entity, user)
            },
            teardown: ->(entity:, user:) {
              EmailSequenceRefinement.cleanup!(entity)
            },
            messages: [
              "I have an email sequence called 'Product Launch Series'. " \
              "Can you show me what's in it — the emails, subject lines, and timing?",

              "OK a few changes: First, the second email subject line is too bland — " \
              "change it to something like 'Your 5-Minute Quick-Start Guide'. " \
              "Also push that email back to 3 days instead of 2. " \
              "And for the third email, add a strong CTA at the end offering " \
              "a free 1-on-1 onboarding call.",
            ],
            assertions: [
              { type: :tool_called, tool_name: "platform_query", min_times: 1 },
              { type: :tool_called, tool_name: "platform_update", min_times: 1 },
              { type: :no_errors },
              { type: :conversation_completed },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate the AI's ability to review and refine an existing email sequence:

              1. DISCOVERY (0-15): Did Turn 1 accurately present the sequence?
                 - Found the 'Product Launch Series' sequence
                 - Showed all 3 emails with their subject lines
                 - Showed the timing/delays correctly (immediate, 2 days, 5 days)
                 - Presented in a clear, readable format

              2. SUBJECT_LINE_EDIT (0-15): Was the second email's subject updated?
                 - Used platform_update on the correct email template
                 - New subject is compelling (close to 'Your 5-Minute Quick-Start Guide')
                 - Didn't change other fields unnecessarily

              3. TIMING_ADJUSTMENT (0-15): Was the second email's delay changed?
                 - Used platform_update on the sequence step (not the template)
                 - Changed delay from 48 hours (2 days) to 72 hours (3 days)
                 - Correctly identified the right step to update

              4. CTA_ADDITION (0-10): Was the third email's content updated?
                 - Used platform_update on the third email template
                 - Added a CTA about a free 1-on-1 onboarding call
                 - Preserved existing content while adding the new CTA

              5. PRECISION (0-10): Did the AI make surgical edits?
                 - Updated only the specific items requested
                 - Did NOT re-create the sequence from scratch
                 - Did NOT modify the first email (which wasn't mentioned)
                 - Confirmed exactly what was changed
            RUBRIC
            timeout_seconds: 180
          )
        end
      end
    end
  end
end
