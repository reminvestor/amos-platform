require 'timeout'

class ImproveGeneratedCodeJob < ApplicationJob
  queue_as :default
  
  discard_on ActiveJob::DeserializationError
  
  # Claude 3.7 Sonnet is the model we'll use
  MODEL = "claude-3-7-sonnet-20250219"
  
  def perform(crawler_job_id)
    crawler_job = CrawlerJob.find_by(id: crawler_job_id)
    
    unless crawler_job
      Rails.logger.warn "ImproveGeneratedCodeJob: Could not find CrawlerJob with ID #{crawler_job_id}. Aborting."
      return
    end
    
    # Ensure job is in a state where improvement makes sense
    unless crawler_job.generated_code.present? && (crawler_job.status == 'improving' || crawler_job.status == 'ready' || crawler_job.status == 'failed')
      Rails.logger.warn "ImproveGeneratedCodeJob: Job #{crawler_job_id} is not in a state for improvement (status: #{crawler_job.status}). Skipping."
      return
    end
    
    # Original description and current code
    original_description = crawler_job.description
    current_code = crawler_job.generated_code
    
    # Log that we're using the original request
    crawler_job.add_log("Including original request: \"#{original_description.truncate(100)}\"", "info")
    
    # Create a ClaudeService instance
    crawler_job.add_log("Initializing Claude client...", "info")
    
    # Check for API key
    unless ENV['ANTHROPIC_API_KEY'].present?
      error_msg = "ANTHROPIC_API_KEY environment variable not set!"
      crawler_job.add_log(error_msg, "error")
      crawler_job.update(status: 'failed', error_message: error_msg)
      return
    end
    
    # Initialize client
    claude_client = ClaudeService.new
    
    Rails.logger.info "ImproveGeneratedCodeJob: Starting code improvement for Job ID: #{crawler_job.id}"
    crawler_job.add_log("Starting code improvement process", "info")
    
    begin
      # Construct the prompt
      crawler_job.add_log("Building prompts for Claude...", "info")
      system_prompt = build_system_prompt
      user_prompt = build_user_prompt(original_description, current_code)
      
      # Log for debugging
      Rails.logger.debug "ImproveGeneratedCodeJob: System prompt: #{system_prompt}"
      Rails.logger.debug "ImproveGeneratedCodeJob: User prompt: #{user_prompt.truncate(300)}"
      
      # Call Claude
      crawler_job.add_log("Sending request to Claude 3.7 Sonnet model...", "info")
      crawler_job.add_log("This may take up to 1-2 minutes depending on Claude's response time", "info")
      
      start_time = Time.current
      improved_content = nil # Declare variable outside the block to fix scope issue
      
      begin
        # Add timeout to prevent indefinite hanging
        Timeout::timeout(120) do # 2 minute timeout
          improved_content = claude_client.send_message(
            system_prompt,
            user_prompt,
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
      
      # Process the improved code
      crawler_job.add_log("Processing improved code from response...", "info")
      
      if improved_content.blank?
        crawler_job.add_log("Error: Claude response did not contain code", "error")
        raise StandardError, "Claude response was empty or malformed."
      end
      
      # Clean up potential markdown code fences
      improved_code = improved_content.gsub(/^```python\n/, '').gsub(/^```\n/, '').gsub(/\n```$/, '').strip
      
      # Log some basic improvements found
      original_lines = current_code.lines.count
      improved_lines = improved_code.lines.count
      line_diff = improved_lines - original_lines
      
      if line_diff > 0
        crawler_job.add_log("The improved code has #{line_diff} more lines (+#{(line_diff.to_f / original_lines * 100).round(1)}%)", "info")
      elsif line_diff < 0
        crawler_job.add_log("The improved code has #{line_diff.abs} fewer lines (-#{(line_diff.abs.to_f / original_lines * 100).round(1)}%)", "info")
      else
        crawler_job.add_log("The improved code has the same number of lines but includes improvements", "info")
      end
      
      # Look for common improvements
      improvements = []
      improvements << "Added user-agent headers" if improved_code.include?('User-Agent') && !current_code.include?('User-Agent')
      improvements << "Enhanced error handling" if improved_code.scan(/except|try/).count > current_code.scan(/except|try/).count
      improvements << "Added rate limiting/delays" if improved_code.scan(/sleep|time.sleep/).count > current_code.scan(/sleep|time.sleep/).count
      improvements << "Improved URL handling" if improved_code.scan(/urljoin|urlparse/).count > current_code.scan(/urljoin|urlparse/).count
      
      # Check for function/method enhancements
      improvements << "Added or improved functions" if improved_code.scan(/def\s+[a-zA-Z_]+/).count > current_code.scan(/def\s+[a-zA-Z_]+/).count
      
      # Check for improved comments
      improvements << "Added better documentation" if improved_code.scan(/#/).count > current_code.scan(/#/).count + 5
      
      # Check for pagination handling
      improvements << "Enhanced pagination handling" if improved_code.scan(/page|pagination|next_page/).count > current_code.scan(/page|pagination|next_page/).count
      
      # Check for better logging
      improvements << "Improved logging" if improved_code.scan(/send_log|log\(/).count > current_code.scan(/send_log|log\(/).count
      
      improvements.each do |improvement|
        crawler_job.add_log("Improvement: #{improvement}", "info")
      end
      
      # Create a summary explanation
      improvement_explanation = if improvements.any?
        improvements.join(". ") + "."
      else
        "General code structure and efficiency improvements."
      end
      
      crawler_job.add_log("Summary of improvements: #{improvement_explanation}", "info")
      
      crawler_job.add_log("Updating crawler job with improved code...", "info")
      
      # Update the crawler job with the improved code
      crawler_job.update(
        generated_code: improved_code,
        status: 'ready',
        error_message: nil,
        fix_explanation: improvement_explanation
      )
      
      crawler_job.add_log("Code has been improved and updated successfully", "info")
      crawler_job.add_log("Ready to test or run the improved code", "info")
      Rails.logger.info "ImproveGeneratedCodeJob: Code improved successfully for Job ID: #{crawler_job.id}"
      
    rescue => e
      error_msg = "Failed to improve code: #{e.message}"
      Rails.logger.error "ImproveGeneratedCodeJob: #{error_msg}"
      Rails.logger.error e.backtrace.join("\n")
      
      crawler_job.add_log(error_msg, "error")
      crawler_job.add_log("Error details: #{e.backtrace.first}", "error") if e.backtrace.present?
      crawler_job.update(status: 'failed', error_message: error_msg)
    end
  end
  
  private
  
  def build_system_prompt
    <<~PROMPT
    You are an expert Python developer tasked with improving a web crawler script.
    The script is meant to extract contact information (first name, last name, email) 
    from websites and send it to an API.
    
    Your job is to enhance the current code to make it more robust, efficient, and effective.
    
    Focus on these improvements:
    1. Better structure and organization of the code
    2. More efficient crawling patterns and algorithms
    3. Enhanced parsing techniques for reliable data extraction
    4. Better rate limiting to avoid being blocked
    5. Proper User-Agent headers and request practices
    6. More comprehensive error handling and recovery
    7. Improved logging for better monitoring
    8. Better pagination handling if applicable
    9. Any optimizations that would make the crawler more effective
    
    IMPORTANT PRODUCTION REQUIREMENTS:
    1. This code will be IMMEDIATELY DEPLOYED to production, so:
       - NEVER use placeholder URLs like "example.com" or "domain.com"
       - Use the actual domains/URLs mentioned in the user's original request
       - Include real, working CSS selectors for the specific sites
       - Add comprehensive error handling for edge cases
       - Include proper User-Agent headers to respect site policies
       - Add rate limiting/delays to avoid getting blocked
    2. All API endpoints in the code must be kept exactly as they are
    3. The authentication and logging mechanisms must be preserved
    
    Output ONLY the complete, improved Python code without any explanation, markdown formatting, or additional text.
    The code should still follow all the original requirements, including sending logs to the API.
    PROMPT
  end
  
  def build_user_prompt(description, current_code)
    <<~PROMPT
    I need to improve a Python web crawler script.
    
    ORIGINAL USER REQUEST:
    #{description}
    
    CURRENT CODE:
    ```python
    #{current_code}
    ```
    
    Please provide an improved version of the code that follows the original requirements
    but is more robust, efficient, and effective at crawling and extracting contact information.
    
    Output only the complete Python code without any explanation or additional text.
    PROMPT
  end
end
