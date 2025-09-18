class ProcessLandingPageSubmissionJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(submission_id)
    submission = LandingPageSubmission.find(submission_id)
    
    Rails.logger.info "Processing landing page submission #{submission_id} for page '#{submission.landing_page.title}'"
    
    # Process the submission and create/update contact
    submission.process_and_create_contact!
    
    Rails.logger.info "Successfully processed submission #{submission_id}, status: #{submission.status}"
    
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Landing page submission #{submission_id} not found"
  rescue => e
    Rails.logger.error "Failed to process landing page submission #{submission_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
end
