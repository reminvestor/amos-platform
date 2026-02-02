# frozen_string_literal: true

module Workflows
  module Executors
    # EnrollInSequenceExecutor - Enrolls contacts in email sequences
    class EnrollInSequenceExecutor < BaseExecutor
      def execute
        log_info "Enrolling contact in email sequence"

        sequence_id = get_value('email_sequence_id') || config[:email_sequence_id]
        contact_id = get_value('contact_id') || inputs[:contact_id]

        return failure("Email sequence ID is required") if sequence_id.blank?
        return failure("Contact ID is required") if contact_id.blank?

        # Find sequence and contact
        sequence = entity.email_sequences.find_by(id: sequence_id)
        return failure("Email sequence not found: #{sequence_id}") unless sequence

        contact = entity.contacts.find_by(id: contact_id)
        return failure("Contact not found: #{contact_id}") unless contact

        # Check if already enrolled
        existing = sequence.sequence_enrollments.find_by(contact_id: contact.id)
        if existing
          return success(
            enrolled: false,
            already_enrolled: true,
            enrollment_id: existing.id,
            enrollment_status: existing.status,
            message: "Contact is already enrolled in this sequence"
          )
        end

        begin
          # Create enrollment
          enrollment = sequence.sequence_enrollments.create!(
            contact: contact,
            entity: entity,
            status: sequence.status == 'active' ? 'active' : 'pending',
            current_step_number: 0
          )

          # If sequence is active, set up first email timing
          if sequence.status == 'active'
            first_step = sequence.sequence_steps.ordered.first
            if first_step
              enrollment.update!(
                current_step_number: first_step.step_number,
                started_at: Time.current,
                next_send_at: Time.current + first_step.delay_hours.hours
              )
            end
          end

          # Update sequence counts
          sequence.update_enrollment_counts

          success(
            enrolled: true,
            enrollment_id: enrollment.id,
            enrollment_status: enrollment.status,
            sequence_name: sequence.name,
            contact_email: contact.email
          )
        rescue ActiveRecord::RecordInvalid => e
          failure("Failed to enroll contact: #{e.message}")
        rescue => e
          log_error "Enrollment failed: #{e.message}"
          failure("Failed to enroll contact: #{e.message}")
        end
      end
    end
  end
end
