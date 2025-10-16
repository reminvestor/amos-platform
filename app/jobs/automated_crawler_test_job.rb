class AutomatedCrawlerTestJob < ApplicationJob
  queue_as :default

  # Maximum number of improvement attempts
  MAX_IMPROVEMENT_ATTEMPTS = 3

  def perform(crawler_job_id)
    Rails.logger.info "AutomatedCrawlerTestJob: Starting for Job ID: #{crawler_job_id}"

    crawler_job = CrawlerJob.find_by(id: crawler_job_id)

    unless crawler_job
      Rails.logger.warn "AutomatedCrawlerTestJob: Could not find CrawlerJob with ID #{crawler_job_id}. Aborting."
      return
    end

    # Make sure we have a crawler to test
    unless crawler_job.status == "ready" && crawler_job.generated_code.present?
      Rails.logger.info "AutomatedCrawlerTestJob: Job #{crawler_job_id} is not ready or has no code. Aborting."
      return
    end

    # Get the current improvement attempts
    current_attempts = crawler_job.improvement_attempts || 0

    # Check if we've reached the maximum attempts
    if current_attempts >= MAX_IMPROVEMENT_ATTEMPTS
      crawler_job.add_log("Reached maximum improvement attempts (#{MAX_IMPROVEMENT_ATTEMPTS}). Marking as ready.", "warning")
      crawler_job.update(status: "ready")
      return
    end

    # Step 1: Run the crawler in debug mode to collect error information
    crawler_job.add_log("Starting automated test cycle - attempt #{current_attempts + 1}/#{MAX_IMPROVEMENT_ATTEMPTS}", "info")
    crawler_job.update(status: "testing")

    # Debug run - collect detailed error output
    run_debug_mode(crawler_job)

    # Step 2: Check if we had any errors
    if crawler_job_has_errors?(crawler_job)
      # Step 3: If we had errors, try to fix them
      crawler_job.add_log("Errors detected. Starting automated bug fixing...", "info")
      crawler_job.update(status: "fixing")

      # Run the bug fixing service
      bug_fix_service = BugFixService.new(crawler_job)
      bug_fix_service.fix_runtime_bugs

      # After fixing, update attempt counter
      crawler_job.update(improvement_attempts: current_attempts + 1)

      # Schedule the next test cycle (only if we haven't reached the max attempts)
      if (current_attempts + 1) < MAX_IMPROVEMENT_ATTEMPTS
        # Add a small delay to allow for any processing
        AutomatedCrawlerTestJob.set(wait: 2.seconds).perform_later(crawler_job.id)
      else
        crawler_job.add_log("Completed maximum improvement attempts. The crawler may still have issues.", "warning")
        crawler_job.update(status: "ready")
      end
    else
      # No errors found - crawler is ready to use
      crawler_job.add_log("No errors detected. Crawler is ready to use.", "info")
      crawler_job.update(status: "ready")
    end
  end

  private

  def run_debug_mode(crawler_job)
    crawler_job.add_log("Running crawler in debug mode...", "info")

    output = nil
    error = nil
    exit_status = nil

    Tempfile.create([ "auto_debug_#{crawler_job.id}_", ".py" ]) do |file|
      file.write(crawler_job.generated_code)
      file.flush

      begin
        # Build the command with environment variables
        env = { "MARKETING_API_KEY" => crawler_job.user.api_key, "CRAWLER_TEST_MODE" => "true" }
        cmd = "python3 #{file.path}"

        # Log the debugging start message
        crawler_job.add_log("Debug execution starting for automated test cycle", "debug")

        # Use a mutex and condition variable for thread synchronization
        mutex = Mutex.new
        resource = ConditionVariable.new
        timeout_reached = false
        cmd_completed = false

        # For partial output collection in case of timeout
        partial_output = []
        partial_error = []

        # Start the command in a separate thread
        thread = Thread.new do
          Open3.popen3(env, cmd) do |stdin, stdout, stderr, wait_thr|
            # Use non-blocking reads with a buffer to collect partial output
            stdout_reader = Thread.new do
              while line = stdout.gets
                mutex.synchronize { partial_output << line.strip }
              end
            end

            stderr_reader = Thread.new do
              while line = stderr.gets
                mutex.synchronize { partial_error << line.strip }
              end
            end

            # Wait for the process to complete
            status = wait_thr.value
            stdout_reader.join(2)
            stderr_reader.join(2)

            # Get full output
            mutex.synchronize do
              unless timeout_reached
                output = partial_output.join("\n")
                error = partial_error.join("\n")
                exit_status = status.exitstatus
                cmd_completed = true
                resource.signal
              end
            end
          end
        end

        # Wait for either completion or timeout
        mutex.synchronize do
          # 60 second timeout
          if !resource.wait(mutex, 60) && !cmd_completed
            timeout_reached = true
            # Use partial output collected so far
            output = partial_output.empty? ? "Command timed out after 60 seconds (no output)" : partial_output.join("\n")
            error = partial_error.empty? ? "Execution exceeded 60 second timeout" : partial_error.join("\n")
            exit_status = -1

            # Try to kill the thread gracefully
            thread.kill if thread.alive?
          end
        end

        # Wait for thread to finish
        thread.join(5)
      rescue => e
        output = ""
        error = "Error executing command: #{e.message}"
        exit_status = -1
      end
    end

    # Save the output as logs
    if output.present?
      output.each_line do |line|
        line = line.strip
        next if line.blank?
        crawler_job.add_log(line, "debug")
      end
    end

    if error.present? && error != ""
      error.each_line do |line|
        line = line.strip
        next if line.blank?
        crawler_job.add_log("ERROR: #{line}", "error")
      end
    end

    # Always log the final status
    crawler_job.add_log("Debug execution completed with exit status: #{exit_status}", exit_status == 0 ? "info" : "error")
  end

  def crawler_job_has_errors?(crawler_job)
    # Look for error logs from the most recent debug run
    recent_error_logs = crawler_job.crawler_job_logs
      .where(log_level: "error")
      .where("created_at > ?", 1.minute.ago)
      .count

    # Look for non-zero exit status messages
    recent_status_logs = crawler_job.crawler_job_logs
      .where("message LIKE ? AND log_level = ?", "%exit status: %", "error")
      .where("created_at > ?", 1.minute.ago)
      .count

    # Return true if we found any errors
    recent_error_logs > 0 || recent_status_logs > 0
  end
end
