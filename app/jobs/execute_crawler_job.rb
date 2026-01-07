require "tempfile"
require "shellwords"
require "fileutils"
require "open3"

class ExecuteCrawlerJob < ApplicationJob
  queue_as :default # Or a dedicated execution queue

  discard_on ActiveJob::DeserializationError

  # Add retries? Maybe not for execution triggers.
  # retry_on SomeError, wait: :exponentially_longer, attempts: 3

  def perform(crawler_job_id)
    crawler_job = CrawlerJob.find_by(id: crawler_job_id)

    unless crawler_job
      Rails.logger.warn "ExecuteCrawlerJob: Could not find CrawlerJob with ID #{crawler_job_id}. Aborting."
      return
    end

    unless crawler_job.status == "ready" && crawler_job.generated_code.present?
      Rails.logger.warn "ExecuteCrawlerJob: Job #{crawler_job_id} is not ready or has no code (status: #{crawler_job.status}). Skipping execution."
      # Optionally update status to failed if it was supposed to be ready
      # crawler_job.update(status: 'failed', error_message: "Attempted to run job but it was not ready or code was missing.")
      return
    end

    user = crawler_job.user
    unless user && user.api_key.present?
      Rails.logger.error "ExecuteCrawlerJob: Cannot run job #{crawler_job_id}, user or user API key is missing."
      crawler_job.update(status: "failed", error_message: "User or API key missing for execution.")
      return
    end

    Rails.logger.info "ExecuteCrawlerJob: Preparing to execute Job ID: #{crawler_job_id}"
    crawler_job.update(status: "queued_for_run")

    # Create initial log
    crawler_job.add_log("Starting crawler execution job preparation", "info")

    # Create a temporary file for the Python script
    Tempfile.create([ "crawler_#{crawler_job.id}_", ".py" ]) do |file|
      file.write(crawler_job.generated_code)
      file.flush # Ensure data is written to disk
      temp_script_path = file.path

      Rails.logger.info "ExecuteCrawlerJob: Wrote generated code to temporary file: #{temp_script_path}"
      crawler_job.add_log("Generated code saved to temporary file", "debug")

      # Determine whether to use Heroku even in development
      use_heroku = Rails.env.production? || ENV["USE_HEROKU_FOR_CRAWLERS"] == "true"

      if use_heroku
        # We need Heroku app name when deploying to Heroku
        heroku_app_name = ENV["HEROKU_APP_NAME"]
        unless heroku_app_name
          error_msg = "HEROKU_APP_NAME environment variable not set! Cannot run command on Heroku."
          Rails.logger.error "ExecuteCrawlerJob: #{error_msg}"
          crawler_job.add_log(error_msg, "error")
          crawler_job.update(status: "failed", error_message: error_msg)
          return
        end

        # Build env var string for Heroku --env flag
        env_vars = "MARKETING_API_KEY=#{user.api_key}"

        # Use array form with Open3 to avoid shell injection - pipe script via stdin
        heroku_cmd = [
          "heroku", "run",
          "--app", heroku_app_name,
          "--env", env_vars,
          "--type=run",
          "--", "python3", "-"
        ]

        crawler_job.add_log("Preparing to execute crawler on Heroku", "info")
        Rails.logger.info "ExecuteCrawlerJob: Executing Heroku command (array form)"

        # Execute with stdin_data to pipe the script content safely
        script_content = File.read(temp_script_path)
        _stdout, _stderr, status = Open3.capture3(*heroku_cmd, stdin_data: script_content)
        success = status.success?
      else
        # In pure local development, run Python directly
        dev_script_path = File.join(Dir.tmpdir, "crawler_#{crawler_job.id}_#{Time.now.to_i}.py")
        FileUtils.cp(temp_script_path, dev_script_path)

        # Use array form with env hash - no shell interpretation
        env_hash = { "MARKETING_API_KEY" => user.api_key }

        Rails.logger.info "Local development - Python script saved to: #{dev_script_path}"
        crawler_job.add_log("Preparing to execute crawler locally with Python", "info")
        Rails.logger.info "ExecuteCrawlerJob: Executing local command (array form with env hash)"

        # Execute with array form - safer than shell string interpolation
        success = system(env_hash, "python3", dev_script_path)
      end

      if success
        msg = use_heroku ?
          "Crawler launched successfully on Heroku. Check logs for progress." :
          "Crawler launched successfully locally. Check logs for progress."

        Rails.logger.info "ExecuteCrawlerJob: #{msg}"
        crawler_job.add_log(msg, "info")

        # Update status to 'running' - relies on the crawler itself to report completion/failure
        crawler_job.update(status: "running", error_message: nil)
      else
        error_msg = use_heroku ?
          "Failed to launch crawler on Heroku. Check if the Heroku CLI is installed and you're logged in." :
          "Failed to launch crawler locally. Check if Python 3 is installed."

        Rails.logger.error "ExecuteCrawlerJob: #{error_msg} Exit status: #{$?.exitstatus}"
        crawler_job.add_log(error_msg, "error")

        # Revert status or set to failed?
        crawler_job.update(status: "failed", error_message: error_msg)
      end
    end # Tempfile is automatically deleted here

  rescue StandardError => e
      error_msg = "Unexpected error: #{e.message}"
      Rails.logger.error "ExecuteCrawlerJob: #{error_msg}"
      Rails.logger.error e.backtrace.join("\n")
      crawler_job.add_log(error_msg, "error")
      crawler_job.update(status: "failed", error_message: error_msg)
  end
end
