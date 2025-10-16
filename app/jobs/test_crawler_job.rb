require "tempfile"
require "shellwords"
require "fileutils"

class TestCrawlerJob < ApplicationJob
  queue_as :default # Or a dedicated testing queue

  discard_on ActiveJob::DeserializationError

  def perform(crawler_job_id)
    crawler_job = CrawlerJob.find_by(id: crawler_job_id)

    unless crawler_job
      Rails.logger.warn "TestCrawlerJob: Could not find CrawlerJob with ID #{crawler_job_id}. Aborting."
      return
    end

    unless crawler_job.status == "ready" && crawler_job.generated_code.present?
      Rails.logger.warn "TestCrawlerJob: Job #{crawler_job_id} is not ready or has no code (status: #{crawler_job.status}). Skipping test."
      # Don't change status here, the UI already prevents triggering
      return
    end

    user = crawler_job.user
    unless user && user.api_key.present?
      Rails.logger.error "TestCrawlerJob: Cannot test job #{crawler_job_id}, user or user API key is missing."
      crawler_job.update(status: "failed", error_message: "User or API key missing for test execution.") # Test failed
      return
    end

    Rails.logger.info "TestCrawlerJob: Preparing to test Job ID: #{crawler_job_id}"
    # Keep status as 'ready' until we know the test launched, or set a specific 'queued_for_test'?
    # Let's use 'testing' to indicate the launch attempt is happening.
    crawler_job.update(status: "testing", error_message: nil)

    # Create a log entry at the start
    crawler_job.add_log("Starting test crawler job preparation", "info")

    # Create a temporary file for the Python script
    Tempfile.create([ "test_crawler_#{crawler_job.id}_", ".py" ]) do |file|
      file.write(crawler_job.generated_code)
      file.flush
      temp_script_path = file.path

      Rails.logger.info "TestCrawlerJob: Wrote generated code to temporary file: #{temp_script_path}"
      crawler_job.add_log("Generated code saved to temporary file", "debug")

      # Determine whether to use Heroku even in development
      use_heroku = Rails.env.production? || ENV["USE_HEROKU_FOR_CRAWLERS"] == "true"

      if use_heroku
        # We need Heroku app name when deploying to Heroku
        heroku_app_name = ENV["HEROKU_APP_NAME"]
        unless heroku_app_name
          error_msg = "HEROKU_APP_NAME environment variable not set! Cannot run command on Heroku."
          Rails.logger.error "TestCrawlerJob: #{error_msg}"
          crawler_job.add_log(error_msg, "error")
          crawler_job.update(status: "failed", error_message: error_msg)
          return
        end

        # Pass API key AND the test mode flag
        # Note: Multiple env vars are separated by spaces within the same --env flag
        env_vars = "MARKETING_API_KEY=#{Shellwords.escape(user.api_key)} CRAWLER_TEST_MODE=true"

        # Always use python3 on Heroku to be explicit
        # Command to run python on Heroku
        command = "heroku run --app #{Shellwords.escape(heroku_app_name)} --env #{Shellwords.escape(env_vars)} --type=run -- python3 #{Shellwords.escape(File.basename(temp_script_path))} < #{Shellwords.escape(temp_script_path)}"

        crawler_job.add_log("Preparing to execute crawler on Heroku", "info")
      else
        # In pure local development, run Python directly
        dev_script_path = File.join(Dir.tmpdir, "test_crawler_#{crawler_job.id}_#{Time.now.to_i}.py")
        FileUtils.cp(temp_script_path, dev_script_path)

        # Set environment variables and run locally with python3
        command = "MARKETING_API_KEY=#{Shellwords.escape(user.api_key)} CRAWLER_TEST_MODE=true python3 #{Shellwords.escape(dev_script_path)}"

        Rails.logger.info "Local development - Python script saved to: #{dev_script_path}"
        crawler_job.add_log("Preparing to execute crawler locally with Python", "info")
      end

      Rails.logger.info "TestCrawlerJob: Executing command: #{command.gsub(user.api_key, '[REDACTED]')}"

      success = system(command)

      if success
        msg = use_heroku ?
          "Test crawler launched successfully on Heroku. Check logs for progress." :
          "Test crawler launched successfully locally. Check logs for progress."

        Rails.logger.info "TestCrawlerJob: #{msg}"
        crawler_job.add_log(msg, "info")

        # Revert to ready for simplicity
        crawler_job.update(status: "ready", error_message: msg)
      else
        error_msg = use_heroku ?
          "Failed to launch test crawler on Heroku. Check if the Heroku CLI is installed and you're logged in." :
          "Failed to launch test crawler locally. Check if Python 3 is installed."

        Rails.logger.error "TestCrawlerJob: #{error_msg} Exit status: #{$?.exitstatus}"
        crawler_job.add_log(error_msg, "error")

        # Test failed to even launch
        crawler_job.update(status: "failed", error_message: error_msg)
      end
    end

  rescue StandardError => e
      error_msg = "Unexpected error: #{e.message}"
      Rails.logger.error "TestCrawlerJob: #{error_msg}"
      Rails.logger.error e.backtrace.join("\n")
      crawler_job.add_log(error_msg, "error")
      crawler_job.update(status: "failed", error_message: error_msg)
  end
end
