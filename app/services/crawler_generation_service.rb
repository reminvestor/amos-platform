require "timeout"

class CrawlerGenerationService
  attr_reader :crawler_job, :user, :claude_client

  # Qwen3-Next with max thinking for complex code generation
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

  def generate_code
    unless @claude_client
      crawler_job.update(status: "failed", error_message: "Claude client not initialized.")
      return
    end

    Rails.logger.info "Starting crawler generation for Job ID: #{crawler_job.id} using model #{MODEL}"
    crawler_job.update(status: "generating", error_message: nil) # Clear previous errors

    begin
      system_prompt = build_prompt
      user_description = crawler_job.description # Keep user description separate for clarity

      Rails.logger.debug "Crawler Job ID: #{crawler_job.id} - System Prompt:\n#{system_prompt}"
      Rails.logger.debug "Crawler Job ID: #{crawler_job.id} - User Description: #{user_description}"

      # --- Call Claude API using our custom service ---
      begin
        # Add timeout to prevent indefinite hanging
        generated_content = nil # Declare variable outside the block to fix scope issue

        Timeout.timeout(120) do # 2 minute timeout
          generated_content = claude_client.send_message(
            system_prompt,
            "Generate the Python script based on this description: #{user_description}",
            model: MODEL,
            max_tokens: 4000,
            temperature: 0.5
          )
        end
      rescue Timeout::Error
        Rails.logger.error "Claude API call timed out after 120 seconds for Job ID: #{crawler_job.id}"
        raise StandardError, "Claude API call timed out after 120 seconds"
      end
      # --- End Claude API Call ---

      if generated_content.blank?
        raise StandardError, "Claude response was empty or malformed."
      end

      # The prompt asks for *only* the code, but sometimes models add markdown fences.
      # Clean up potential markdown code fences (```python ... ``` or ``` ... ```)
      cleaned_code = generated_content.gsub(/^```python\n/, "").gsub(/^```\n/, "").gsub(/\n```$/, "").strip

      Rails.logger.info "Successfully received code from Claude for Job ID: #{crawler_job.id}"
      Rails.logger.debug "Crawler Job ID: #{crawler_job.id} - Raw Response Snippet: #{generated_content.truncate(200)}"
      Rails.logger.debug "Crawler Job ID: #{crawler_job.id} - Cleaned Code Snippet: #{cleaned_code.truncate(200)}"

      # Basic validation: Check if it looks somewhat like Python code
      unless looks_like_python?(cleaned_code)
         Rails.logger.warn "Crawler Job ID: #{crawler_job.id} - Generated content doesn't look like Python code."
        # Keep the raw content for debugging in this case?
        # Or fail the job?
      end

      crawler_job.update!(
        generated_code: cleaned_code,
        status: "ready" # Code is generated, ready for execution
      )
      Rails.logger.info "Crawler code generated and saved for Job ID: #{crawler_job.id}"

    rescue StandardError => e
      # Handle other potential errors (network, parsing, etc.)
      Rails.logger.error "Error generating crawler code for Job ID: #{crawler_job.id} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      crawler_job.update(status: "failed", error_message: "Internal Error: #{e.message}")
    end
  end

  private

  def build_prompt
    # Updated prompt: API key comes from environment variable, includes logging to API
    <<~PROMPT
    You are an expert Python developer tasked with writing web crawler scripts.
    Generate a complete Python script based on the user's request provided in the next message.

    The script MUST:
    1. Use the `requests` library for fetching HTML and `BeautifulSoup4` for parsing.
    2. Define functions to extract First Name, Last Name, and Email Address from the HTML structure of the target website(s) described by the user.
    3. If the user's request implies multiple pages (e.g., search results), include logic to handle pagination if possible based on the site's structure.
    4. Store the extracted contacts as a list of dictionaries: `[{'first_name': '...', 'last_name': '...', 'email': '...'}]`.
    5. Include a function `send_contacts_to_api(contacts_list)` that sends the extracted data via POST requests to the endpoint: `#{api_endpoint}`.
    6. **CRITICALLY IMPORTANT:** The API key for authentication MUST be read from an environment variable named `MARKETING_API_KEY`. The script must include the header `Authorization: Bearer <API_KEY_FROM_ENV>` in the POST request. **DO NOT hardcode any API key in the script.**
    7. The POST request body MUST be JSON formatted like: `{'contact': {'first_name': '...', 'last_name': '...', 'email': '...'}}`. Send contacts one by one or in small batches to avoid large requests.
    8. Include robust error handling (e.g., for network errors, parsing errors, missing environment variable).
    9. **LOGGING FEATURE:** The script must include a function named `send_log(message, level='info')` that sends log messages to our application's API.#{' '}
       - The logging endpoint is: `#{logging_endpoint(@crawler_job.id)}`
       - Send POST requests with JSON data formatted as: `{'log': {'message': '...', 'level': '...'}}`
       - Include the same `Authorization: Bearer <API_KEY_FROM_ENV>` header
       - Use log levels: 'debug', 'info', 'warning', 'error'
       - Call this logging function frequently (at least every 5-10 seconds during execution) to provide status updates
       - Always log: start/end of crawling, each page visited, contacts found, and any errors
    10. **TEST MODE:** The script must check for an environment variable `CRAWLER_TEST_MODE`. If set to "true":
        - The script should run normally but print all extracted contacts
        - It should run a shorter/limited version of the crawl (e.g., only first page or limited number of results)
        - It should still send logs to the logging API
        - It should NOT send contacts to the API endpoint (skip the `send_contacts_to_api` call)
    11. Print log messages to standard output in addition to sending them to the API.
    12. Be a single, executable Python script, including all necessary imports (`requests`, `BeautifulSoup`, `json`, `os`, `time`).
    13. Check for the `MARKETING_API_KEY` environment variable at the start and exit gracefully if it's not set.
    14. **PRODUCTION-READY CODE:** This code will be IMMEDIATELY DEPLOYED to production, so:
        - NEVER use placeholder URLs like "example.com" or "domain.com"
        - Use the actual domains/URLs mentioned in the user's request
        - Include real, working CSS selectors for the specific sites
        - Add comprehensive error handling for edge cases
        - Include proper User-Agent headers to respect site policies
        - Add rate limiting/delays to avoid getting blocked

    Output ONLY the raw Python code. Do not include ```python markdown fences or any introductory text, explanations, or comments outside the code itself (use comments *within* the code).
    PROMPT
  end

  def api_endpoint
    # Construct the full URL for the API endpoint
    host = ENV["APPLICATION_HOST"] || "localhost:3000" # Adjust default as needed
    protocol = Rails.env.production? ? "https" : "http"
    # Use Rails URL helpers if possible, otherwise fallback
    begin
      Rails.application.routes.url_helpers.url_for(
        controller: "api/v1/crawler_contacts",
        action: "create",
        host: host,
        protocol: protocol,
        only_path: false
      )
    rescue
      "#{protocol}://#{host}/api/v1/crawler_contacts"
    end
  end

  # Helper for generating the logging endpoint URL
  def logging_endpoint(crawler_job_id)
    host = ENV["APPLICATION_HOST"] || "localhost:3000"
    protocol = Rails.env.production? ? "https" : "http"

    begin
      Rails.application.routes.url_helpers.url_for(
        controller: "api/v1/crawler_job_logs",
        action: "create",
        id: crawler_job_id,
        host: host,
        protocol: protocol,
        only_path: false
      )
    rescue
      "#{protocol}://#{host}/api/v1/crawler_jobs/#{crawler_job_id}/logs"
    end
  end

  # Basic sanity check for generated code
  def looks_like_python?(code)
    # Simple checks - can be made more robust
    code.include?("import requests") &&
    code.include?("BeautifulSoup") &&
    code.include?("def ") &&
    code.include?("if __name__ == '__main__':")
  end
end
