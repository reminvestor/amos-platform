# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class ErrorRecoveryMidWorkflow
        TEST_EMAILS = %w[alice@test.com charlie@test.com].freeze

        def self.cleanup!(entity)
          ContactGroup.where(entity: entity, name: "Test Group").find_each do |g|
            g.contacts.clear
            CampaignGroup.where(contact_group_id: g.id).delete_all rescue nil
            g.destroy
          rescue => e
            Rails.logger.debug "[BenchmarkCleanup] ContactGroup #{g.id}: #{e.message}"
          end

          Contact.where(entity: entity, email: TEST_EMAILS).find_each do |c|
            ActiveRecord::Base.connection.execute(
              "DELETE FROM contact_groups_contacts WHERE contact_id = #{c.id}"
            )
            c.destroy
          rescue => e
            Rails.logger.debug "[BenchmarkCleanup] Contact #{c.id}: #{e.message}"
          end
        rescue => e
          Rails.logger.warn "[BenchmarkCleanup] error_recovery cleanup failed: #{e.message}"
        end

        def self.build
          Scenario.new(
            id: :error_recovery_mid_workflow,
            level: :L4,
            category: :error_recovery,
            name: "Recover from error during multi-step workflow",
            description: "Tests resilience: the AI starts a multi-step task, encounters " \
                         "a problem (invalid data), and must recover gracefully without " \
                         "losing progress or confusing the user.",
            tags: [],
            setup: ->(entity:, user:) {
              ErrorRecoveryMidWorkflow.cleanup!(entity)
            },
            messages: [
              "Create 3 contacts for me: Alice (alice@test.com), Bob (invalid-email-format), " \
              "and Charlie (charlie@test.com). Then create a group called 'Test Group' with all of them.",
              "Just skip Bob and add the other two to the group.",
            ],
            assertions: [
              { type: :record_exists, model: "Contact", conditions: {}, min_count: 2 },
              { type: :tool_called, tool_name: "platform_create", min_times: 1 },
              { type: :no_errors },
              { type: :conversation_completed },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate error recovery during a multi-step workflow:
              1. ERROR HANDLING (0-20): Did the AI handle the invalid email gracefully?
                 - Identified that Bob's email is invalid
                 - Didn't crash or abandon the entire task
                 - Communicated the issue clearly to the user
              2. RECOVERY (0-20): Did the AI recover correctly after user guidance?
                 - Created Alice and Charlie successfully
                 - Skipped Bob as instructed
                 - Created the group with the valid contacts
              3. PROGRESS PRESERVATION (0-15): Was earlier work preserved?
                 - Contacts created before the error were not lost
                 - Didn't restart the entire workflow from scratch
              4. COMMUNICATION (0-10): Was the error communicated well?
                 - Explained what went wrong specifically
                 - Asked how the user wanted to proceed
                 - Confirmed the final state after recovery
            RUBRIC
            timeout_seconds: 180
          )
        end
      end
    end
  end
end
