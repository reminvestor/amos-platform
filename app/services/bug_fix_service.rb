require "timeout"

class BugFixService
  attr_reader :crawler_job, :user, :claude_client

  # Qwen3-Next with max thinking for complex debugging
  MODEL = "qwen3-next-80b"

  def initialize(crawler_job)
    @crawler_job = crawler_job
    @user = crawler_job.user

    # Initialize the Claude client
    unless ENV["ANTHROPIC_API_KEY"]
      Rails.logger.error "ANTHROPIC_API_KEY environment variable not set!"
      return
    end

    # Create a ClaudeService instance
    @claude_client = AiServiceHelper.get_service
  end

  def fix_runtime_bugs
    unless @claude_client
      crawler_job.update(status: "failed", error_message: "Claude client not initialized.")
      return
    end

    Rails.logger.info "Starting runtime bug fixing for Job ID: #{crawler_job.id} using model #{MODEL}"
    crawler_job.update(status: "fixing", error_message: nil) # Clear previous errors

    begin
      system_prompt = build_prompt

      # Find the most recent debug execution logs
      recent_logs = get_last_execution_logs

      if recent_logs.empty?
        message = "No execution logs found to analyze bugs. Please run the crawler in debug mode first."
        crawler_job.add_log(message, "warning")
        crawler_job.update(status: "ready", error_message: message)
        return
      end

      crawler_job.add_log("Found #{recent_logs.count} recent execution logs to analyze", "info")

      # Original code and execution logs for Claude
      current_code = crawler_job.generated_code

      # --- Call Claude API using our custom service ---
      crawler_job.add_log("Sending request to Claude 3.7 Sonnet model...", "info")
      crawler_job.add_log("This may take up to 1-2 minutes depending on Claude's response time", "info")

      start_time = Time.current
      fixed_content = nil # Declare variable outside the block to fix scope issue

      begin
        # Add timeout to prevent indefinite hanging
        Timeout.timeout(120) do # 2 minute timeout
          fixed_content = claude_client.send_message(
            system_prompt,
            build_user_prompt(current_code, recent_logs),
            model: MODEL,
            max_tokens: 4000,
            temperature: 0.5
          )
        end
      rescue Timeout::Error
        crawler_job.add_log("API call to Claude timed out after 120 seconds", "error")
        raise StandardError, "Claude API call timed out after 120 seconds"
      end

      elapsed_time = Time.current - start_time
      crawler_job.add_log("Received response from Claude (took #{elapsed_time.round(2)} seconds)", "info")

      # Process the fixed code
      crawler_job.add_log("Processing fixed code from response...", "info")

      if fixed_content.blank?
        crawler_job.add_log("Error: Claude response did not contain code", "error")
        raise StandardError, "Claude response was empty or malformed."
      end

      # Clean up potential markdown code fences
      fixed_code = fixed_content.gsub(/^```python\n/, "").gsub(/^```\n/, "").gsub(/\n```$/, "").strip

      # Generate explanation of changes
      explanation = generate_fix_explanation(current_code, fixed_code, recent_logs)
      crawler_job.add_log("Changes made: #{explanation}", "info")

      # Log changes found
      original_lines = current_code.lines.count
      fixed_lines = fixed_code.lines.count
      line_diff = fixed_lines - original_lines

      if line_diff != 0
        crawler_job.add_log("The fixed code has #{line_diff.abs} #{line_diff > 0 ? 'more' : 'fewer'} lines", "info")
      else
        crawler_job.add_log("The fixed code has the same number of lines but includes bug fixes", "info")
      end

      # Update the crawler job with the fixed code and explanation
      crawler_job.update(
        generated_code: fixed_code,
        status: "ready",
        error_message: nil,
        fix_explanation: explanation
      )

      crawler_job.add_log("Code has been fixed for runtime bugs", "info")
      crawler_job.add_log("Ready to test the fixed code", "info")

    rescue => e
      error_msg = "Failed to fix runtime bugs: #{e.message}"
      Rails.logger.error "BugFixService: #{error_msg}"
      Rails.logger.error e.backtrace.join("\n")

      crawler_job.add_log(error_msg, "error")
      crawler_job.add_log("Error details: #{e.backtrace.first}", "error") if e.backtrace.present?
      crawler_job.update(status: "failed", error_message: error_msg)
    end
  end

  private

  # Get the logs from the most recent execution only
  def get_last_execution_logs
    # Find the last "Debug execution starting" log entry
    last_debug_start = crawler_job.crawler_job_logs
      .where("message LIKE ?", "Debug execution starting%")
      .order(created_at: :desc)
      .first

    return [] unless last_debug_start

    # Get all logs after this one
    crawler_job.crawler_job_logs
      .where("created_at >= ?", last_debug_start.created_at)
      .order(created_at: :asc)
      .pluck(:message, :log_level)
      .map { |msg, level| "#{level.upcase}: #{msg}" }
  end

  def build_prompt
    <<~PROMPT
    You are an expert Python developer tasked with fixing runtime bugs in a web crawler script.
    The script has been executed and encountered errors, which are captured in the execution logs.

    Your job is to analyze the runtime errors in the logs and modify the code to fix these specific issues.

    Common runtime issues to address:
    1. ImportError - Missing libraries or incorrect imports
    2. NameError - Undefined variables or function names
    3. AttributeError - Accessing non-existent properties or methods
    4. TypeError - Incorrect data types or function arguments
    5. IndexError/KeyError - Invalid indexing or dictionary keys
    6. HTTPError - Issues with web requests (status codes, timeouts)
    7. ValueError - Incorrect values passed to functions
    8. Syntax errors in the Python code
    9. ConnectionError - Network connectivity issues
    10. JSON parsing errors

    IMPORTANT PRODUCTION REQUIREMENTS:
    1. This code will be IMMEDIATELY DEPLOYED to production, so:
       - NEVER use placeholder URLs like "example.com" or "domain.com"
       - Use the actual domains/URLs already in the code
       - Keep any existing, working CSS selectors
       - Maintain comprehensive error handling
       - Preserve proper User-Agent headers
       - Keep rate limiting/delays to avoid getting blocked
    2. All API endpoints in the code must be kept exactly as they are
    3. The authentication and logging mechanisms must be preserved
    4. Focus ONLY on fixing the runtime errors shown in the logs

    Output ONLY the complete, fixed Python code without any explanation, markdown formatting, or additional text.
    PROMPT
  end

  def build_user_prompt(current_code, execution_logs)
    <<~PROMPT
    I need to fix the runtime bugs in this Python web crawler script.

    CURRENT CODE:
    ```python
    #{current_code}
    ```

    EXECUTION LOGS (most recent run only):
    ```
    #{execution_logs.join("\n")}
    ```

    Please fix the runtime errors shown in the logs.#{' '}
    Output only the complete Python code without any explanation or additional text.
    PROMPT
  end

  # Generate a human-readable explanation of the fixes applied
  def generate_fix_explanation(original_code, fixed_code, error_logs)
    # Collect error types from logs
    error_types = extract_error_types(error_logs)

    # Compare imports to identify added libraries
    original_imports = extract_imports(original_code)
    fixed_imports = extract_imports(fixed_code)
    new_imports = fixed_imports - original_imports

    # Look for common fixes
    fixes = []

    # Added imports
    if new_imports.any?
      fixes << "Added missing imports: #{new_imports.join(', ')}"
    end

    # Error handling improvements
    if fixed_code.scan(/try|except/).count > original_code.scan(/try|except/).count
      fixes << "Enhanced error handling"
    end

    # Fixed requests/network issues
    if fixed_code.scan(/timeout|retries/).count > original_code.scan(/timeout|retries/).count
      fixes << "Added request timeouts/retries"
    end

    # Added User-Agent
    if fixed_code.include?("User-Agent") && !original_code.include?("User-Agent")
      fixes << "Added proper User-Agent headers"
    end

    # URL parsing fixes
    if fixed_code.scan(/urlparse|urljoin/).count > original_code.scan(/urlparse|urljoin/).count
      fixes << "Improved URL handling"
    end

    # Fixed variable naming/references
    if error_types.include?("NameError") || error_types.include?("UnboundLocalError")
      fixes << "Fixed variable references/naming issues"
    end

    # For cases where specific patterns don't match but changes were made
    if fixes.empty? && fixed_code != original_code
      if error_types.any?
        fixes << "Fixed #{error_types.join(', ')} errors"
      else
        fixes << "Applied general bug fixes"
      end
    end

    # Return formatted explanation
    fixes.join(". ") + "."
  end

  def extract_error_types(logs)
    error_patterns = {
      "ImportError" => /ImportError|No module named/i,
      "NameError" => /NameError|not defined|undefined variable/i,
      "AttributeError" => /AttributeError|has no attribute/i,
      "TypeError" => /TypeError|not callable|NoneType/i,
      "IndexError" => /IndexError|list index out of range/i,
      "KeyError" => /KeyError|key not found/i,
      "ValueError" => /ValueError/i,
      "SyntaxError" => /SyntaxError/i,
      "ConnectionError" => /ConnectionError|Connection refused/i,
      "HTTPError" => /HTTPError|Status code/i,
      "UnboundLocalError" => /UnboundLocalError/i,
      "JSONDecodeError" => /JSONDecodeError|JSON/i
    }

    found_errors = []
    error_patterns.each do |error_name, pattern|
      if logs.any? { |log| log =~ pattern }
        found_errors << error_name
      end
    end

    found_errors
  end

  def extract_imports(code)
    imports = []
    code.lines.each do |line|
      if line =~ /^import\s+(\S+)/ || line =~ /^from\s+(\S+)\s+import/
        imports << $1
      end
    end
    imports
  end
end
