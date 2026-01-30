# frozen_string_literal: true

# ProcessSequenceEnrollmentsJob
#
# Processes pending enrollments when a sequence is activated.
# Sets all pending enrollments to active and schedules their first email.
#
# Usage:
#   ProcessSequenceEnrollmentsJob.perform_later(email_sequence_id)
#
class ProcessSequenceEnrollmentsJob < ApplicationJob
  queue_as :email_sequences

  def perform(email_sequence_id)
    sequence = EmailSequence.find_by(id: email_sequence_id)
    
    unless sequence
      Rails.logger.warn "[ProcessSequenceEnrollments] Sequence #{email_sequence_id} not found"
      return
    end

    unless sequence.status == 'active'
      Rails.logger.info "[ProcessSequenceEnrollments] Sequence #{sequence.id} is not active (status: #{sequence.status})"
      return
    end

    Rails.logger.info "[ProcessSequenceEnrollments] Processing enrollments for sequence #{sequence.id} (#{sequence.name})"

    # Get the first step to determine initial timing
    first_step = sequence.sequence_steps.ordered.first
    
    unless first_step
      Rails.logger.warn "[ProcessSequenceEnrollments] Sequence #{sequence.id} has no steps"
      return
    end

    processed = 0
    errors = 0

    # Activate all pending enrollments
    sequence.sequence_enrollments.pending.find_each do |enrollment|
      begin
        # Calculate when first email should be sent
        first_send_at = if first_step.delay_hours.zero?
          Time.current
        else
          Time.current + first_step.delay_hours.hours
        end

        enrollment.update!(
          status: 'active',
          started_at: Time.current,
          current_step_number: first_step.step_number,
          next_send_at: first_send_at
        )
        processed += 1
      rescue => e
        Rails.logger.error "[ProcessSequenceEnrollments] Failed to activate enrollment #{enrollment.id}: #{e.message}"
        errors += 1
      end
    end

    # Update sequence enrollment counts
    sequence.update_enrollment_counts

    Rails.logger.info "[ProcessSequenceEnrollments] Activated #{processed} enrollments, #{errors} errors"

    # Trigger immediate email sending if any enrollments are ready now
    if sequence.sequence_enrollments.ready_to_send.exists?
      SendSequenceEmailsJob.perform_later(email_sequence_id)
    end
  end
end
