# frozen_string_literal: true

# SendSequenceEmailsJob
#
# Sends emails for sequence enrollments that are ready (next_send_at <= now).
# This job runs on a recurring schedule to process all active sequences.
#
# Usage:
#   SendSequenceEmailsJob.perform_later # Process all ready enrollments
#   SendSequenceEmailsJob.perform_later(email_sequence_id) # Process specific sequence
#
class SendSequenceEmailsJob < ApplicationJob
  queue_as :email_sequences

  # Maximum emails to send per job run (prevents runaway execution)
  MAX_EMAILS_PER_RUN = 100
  
  # Batch size for processing enrollments
  BATCH_SIZE = 25

  def perform(email_sequence_id = nil)
    Rails.logger.info "[SendSequenceEmails] Starting email sequence processing"

    # Get enrollments ready to send
    enrollments = if email_sequence_id.present?
      sequence = EmailSequence.find_by(id: email_sequence_id)
      return unless sequence&.status == 'active'
      
      sequence.sequence_enrollments.ready_to_send.includes(:contact, :email_sequence)
    else
      # Process all active sequences
      SequenceEnrollment.ready_to_send
        .joins(:email_sequence)
        .where(email_sequences: { status: 'active' })
        .includes(:contact, :email_sequence)
    end

    sent_count = 0
    error_count = 0
    skipped_count = 0

    enrollments.limit(MAX_EMAILS_PER_RUN).find_each(batch_size: BATCH_SIZE) do |enrollment|
      begin
        result = send_email_for_enrollment(enrollment)
        
        case result[:status]
        when :sent
          sent_count += 1
        when :skipped
          skipped_count += 1
        when :error
          error_count += 1
        end
      rescue => e
        Rails.logger.error "[SendSequenceEmails] Error processing enrollment #{enrollment.id}: #{e.message}"
        error_count += 1
      end
    end

    Rails.logger.info "[SendSequenceEmails] Complete - Sent: #{sent_count}, Skipped: #{skipped_count}, Errors: #{error_count}"

    # If we hit the max, there may be more to process
    if sent_count + error_count >= MAX_EMAILS_PER_RUN
      Rails.logger.info "[SendSequenceEmails] Hit max limit, scheduling follow-up job"
      SendSequenceEmailsJob.set(wait: 1.minute).perform_later(email_sequence_id)
    end
  end

  private

  def send_email_for_enrollment(enrollment)
    contact = enrollment.contact
    sequence = enrollment.email_sequence
    current_step = enrollment.current_step

    # Validate we have everything needed
    unless current_step
      Rails.logger.warn "[SendSequenceEmails] No current step for enrollment #{enrollment.id}"
      enrollment.complete!
      return { status: :skipped, reason: 'no_current_step' }
    end

    # Skip if contact opted out
    if contact.opted_out?
      Rails.logger.info "[SendSequenceEmails] Skipping opted-out contact #{contact.id}"
      enrollment.cancel!
      return { status: :skipped, reason: 'opted_out' }
    end

    # Skip if contact has no email
    if contact.email.blank?
      Rails.logger.warn "[SendSequenceEmails] Contact #{contact.id} has no email"
      return { status: :skipped, reason: 'no_email' }
    end

    # Get email content
    subject = current_step.effective_subject
    body = current_step.effective_body

    unless subject.present? && body.present?
      Rails.logger.error "[SendSequenceEmails] Step #{current_step.id} missing subject or body"
      return { status: :error, reason: 'missing_content' }
    end

    # Create delivery record for tracking
    delivery = SequenceEmailDelivery.create!(
      email_sequence: sequence,
      sequence_step: current_step,
      sequence_enrollment: enrollment,
      contact: contact,
      entity: sequence.entity,
      status: 'pending'
    )

    # Send the email using the delivery record
    begin
      # Queue the email - SES will handle tracking via Configuration Sets
      message = SequenceMailer.sequence_email(delivery).deliver_now
      
      # Capture SES message ID from the response
      ses_message_id = message&.message_id
      delivery.mark_as_sent(ses_message_id)

      # Update step metrics
      current_step.increment_sent!

      # Record activity
      create_email_activity(contact, sequence, current_step, delivery)

      # Advance to next step
      enrollment.advance_to_next_step!

      Rails.logger.info "[SendSequenceEmails] Sent step #{current_step.step_number} to #{contact.email} (enrollment #{enrollment.id}, delivery #{delivery.id})"

      { status: :sent, contact_id: contact.id, step_number: current_step.step_number, delivery_id: delivery.id }
    rescue => e
      Rails.logger.error "[SendSequenceEmails] Failed to send email: #{e.message}"
      delivery.mark_as_failed(e.message)
      { status: :error, reason: e.message }
    end
  end

  def create_email_activity(contact, sequence, step, delivery)
    Activity.create!(
      entity: sequence.entity,
      contact: contact,
      activity_type: 'email_sent',
      subject: "Sequence email: #{step.effective_subject}",
      description: "Sent step #{step.step_number} of sequence '#{sequence.name}'",
      status: 'completed',
      completed_at: Time.current,
      metadata: {
        sequence_id: sequence.id,
        sequence_name: sequence.name,
        step_number: step.step_number,
        delivery_id: delivery.id
      }
    )
  rescue => e
    Rails.logger.warn "[SendSequenceEmails] Failed to create activity: #{e.message}"
  end
end
