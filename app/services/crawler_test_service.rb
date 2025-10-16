require "timeout"
require "open3"

class CrawlerTestService
  attr_reader :crawler_job, :user

  # Max attempts for improving the crawler
  MAX_IMPROVEMENT_ATTEMPTS = 3

  def initialize(crawler_job)
    @crawler_job = crawler_job
    @user = crawler_job.user
  end

  def run_test_cycle
    # Start the first test
    crawler_job.update(status: "testing")
    test_result = run_test

    # Parse and record the results
    parse_results(test_result)

    # If test has errors, try to improve
    if test_has_errors?(test_result)
      attempt_improvements
    else
      # Mark as ready if there are no errors
      crawler_job.add_log("Crawler test completed successfully. Ready to use.", "info")
      crawler_job.update(status: "ready", error_message: nil)
    end
  end

  private

  # Run the test with timeout
  def run_test
    crawler_job.add_log("Starting test execution...", "info")

    output = nil
    error = nil
    exit_status = nil

    # Create a temporary file for the code
    Tempfile.create([ "test_crawler_#{crawler_job.id}_", ".py" ]) do |file|
      file.write(crawler_job.generated_code)
      file.flush

      # Set environment variables and run with a timeout
      env = {
        "MARKETING_API_KEY" => user.api_key,
        "CRAWLER_TEST_MODE" => "true"
      }
      cmd = "python3 #{file.path}"

      # Use a mutex and condition variable for thread synchronization
      mutex = Mutex.new
      resource = ConditionVariable.new
      timeout_reached = false
      cmd_completed = false

      # Start the command in a separate thread
      thread = Thread.new do
        Open3.popen3(env, cmd) do |stdin, stdout, stderr, wait_thr|
          stdout_data = stdout.read
          stderr_data = stderr.read
          status = wait_thr.value

          mutex.synchronize do
            unless timeout_reached
              output = stdout_data
              error = stderr_data
              exit_status = status.exitstatus
              cmd_completed = true
              resource.signal
            end
          end
        end
      end

      # Wait for either completion or timeout (60 seconds)
      mutex.synchronize do
        if !resource.wait(mutex, 60) && !cmd_completed
          timeout_reached = true
          output = "Command timed out after 60 seconds"
          error = "Execution exceeded 60 second timeout"
          exit_status = -1

          # Try to kill the thread gracefully
          thread.kill if thread.alive?
        end
      end

      # Wait for thread to finish (it should be done already)
      thread.join(5)
    end

    # Log the output and errors
    log_test_output(output, error, exit_status)

    # Return all the information about the test
    {
      output: output,
      error: error,
      exit_status: exit_status,
      timestamp: Time.current
    }
  end

  # Log the output to crawler job logs
  def log_test_output(output, error, exit_status)
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
    status_level = exit_status == 0 ? "info" : "error"
    crawler_job.add_log("Test execution completed with exit status: #{exit_status}", status_level)
  end

  # Parse the test results and store them
  def parse_results(test_result)
    # Store the complete test results
    crawler_job.update(
      test_results: test_result.to_json
    )

    # If there was an error, update the error message
    if test_result[:exit_status] != 0
      crawler_job.update(
        error_message: "Test failed with exit status #{test_result[:exit_status]}"
      )
    end
  end

  # Check if the test has errors
  def test_has_errors?(test_result)
    # Check exit status
    return true if test_result[:exit_status] != 0

    # Check for error messages
    if test_result[:error].present? && test_result[:error] != ""
      return true unless test_result[:error].match?(/\A\s*\z/) # Check if only whitespace
    end

    # Look for specific error indicators in the output
    error_patterns = [
      /\bError\b/i,
      /\bException\b/i,
      /\bTraceback\b/i,
      /\bFailed\b/i
    ]

    if test_result[:output].present?
      error_patterns.each do |pattern|
        return true if test_result[:output].match?(pattern)
      end
    end

    false
  end

  # Attempt to improve the crawler code if it has errors
  def attempt_improvements
    current_attempts = crawler_job.improvement_attempts || 0

    if current_attempts >= MAX_IMPROVEMENT_ATTEMPTS
      crawler_job.add_log("Reached maximum improvement attempts (#{MAX_IMPROVEMENT_ATTEMPTS}). Marking as failed.", "warning")
      crawler_job.update(status: "failed", error_message: "Could not fix all issues after #{MAX_IMPROVEMENT_ATTEMPTS} attempts")
      return
    end

    # Increment the attempt counter
    crawler_job.update(improvement_attempts: current_attempts + 1)
    crawler_job.add_log("Starting improvement attempt #{current_attempts + 1}/#{MAX_IMPROVEMENT_ATTEMPTS}", "info")

    # Use the BugFixService to fix any runtime issues
    crawler_job.update(status: "fixing")
    bug_fix_service = BugFixService.new(crawler_job)
    bug_fix_service.fix_runtime_bugs

    # After fixing, test again
    crawler_job.update(status: "testing")
    test_result = run_test

    # Parse and record the results
    parse_results(test_result)

    # Check if we need another round of improvement
    if test_has_errors?(test_result)
      attempt_improvements
    else
      # Mark as ready if there are no errors
      crawler_job.add_log("Crawler test completed successfully after #{current_attempts + 1} improvement attempts.", "info")
      crawler_job.update(status: "ready", error_message: nil)
    end
  end
end
