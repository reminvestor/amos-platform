class GenerateCrawlerCodeJob < ApplicationJob
  queue_as :default # Or a dedicated queue like :crawler_generation

  discard_on ActiveJob::DeserializationError # Don't retry if the job record is gone

  def perform(crawler_job_id)
    # Add this line for basic output test
    puts "--- GenerateCrawlerCodeJob starting perform for ID: #{crawler_job_id} ---" 
    Rails.logger.info "GenerateCrawlerCodeJob: Starting generation for Job ID: #{crawler_job_id}"
    
    crawler_job = CrawlerJob.find_by(id: crawler_job_id)
    
    unless crawler_job
      # Add puts for errors too
      puts "!!! GenerateCrawlerCodeJob ERROR: Could not find CrawlerJob with ID #{crawler_job_id}. Aborting. !!!"
      Rails.logger.warn "GenerateCrawlerCodeJob: Could not find CrawlerJob with ID #{crawler_job_id}. Aborting."
      return
    end
    
    # Ensure we don't re-run if already generating or completed
    unless crawler_job.status == 'pending' || crawler_job.status == 'generating'
      puts "--- GenerateCrawlerCodeJob SKIPPING: Job #{crawler_job_id} not pending or generating (status: #{crawler_job.status}). ---"
      Rails.logger.info "GenerateCrawlerCodeJob: Job #{crawler_job_id} is not pending or generating (status: #{crawler_job.status}). Skipping generation."
      return
    end

    # Generate the crawler code
    puts "--- GenerateCrawlerCodeJob: Calling CrawlerGenerationService for Job ID: #{crawler_job_id} ---"
    crawler_job.add_log("Starting code generation...", "info")
    CrawlerGenerationService.new(crawler_job).generate_code
    
    # If code generation was successful, start automated testing and fixing cycle
    if crawler_job.status == 'ready' && crawler_job.generated_code.present?
      crawler_job.add_log("Code generation completed successfully. Starting automated testing and bug fixing cycle...", "info")
      crawler_job.update(improvement_attempts: 0) # Reset improvement attempts
      
      # Start the automated test/debug/fix cycle
      AutomatedCrawlerTestJob.perform_later(crawler_job.id)
    end
    
    puts "--- GenerateCrawlerCodeJob: Finished generation process for Job ID: #{crawler_job_id} ---"
    Rails.logger.info "GenerateCrawlerCodeJob: Finished generation process for Job ID: #{crawler_job_id}"
  end
end
