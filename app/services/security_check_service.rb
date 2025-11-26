class SecurityCheckService
  def initialize
    @bedrock_service = BedrockService.new
  end

  def evaluate_tool(tool_definition)
    prompt = build_prompt(tool_definition)
    
    # Using a simple message structure for the security check
    messages = [
      {
        role: "user",
        content: prompt
      }
    ]
    
    # Invoke Bedrock with json_mode hint (handled by system prompt injection in BedrockService)
    response_content = @bedrock_service.send_message(
      nil, # No separate system prompt, included in prompt or handled by json_mode
      messages,
      model: "claude-sonnet-4-5", # Use the correct model name
      temperature: 0.0, # Deterministic output
      json_mode: true
    )
    
    parse_response(response_content)
  rescue => e
    Rails.logger.error "Security Check Failed: #{e.message}"
    # Fail open or closed? Closed is safer.
    {
      "rating" => "fail",
      "reason" => "Security check failed to execute: #{e.message}"
    }
  end

  private

  def build_prompt(tool)
    code_content = if tool.execution_type == 'ruby_code'
                     tool.code
                   else
                     tool.api_config.to_json
                   end

    <<~PROMPT
      You are a Senior Security Engineer. Your job is to audit code for security vulnerabilities in a Ruby on Rails environment.
      
      Review the following tool definition:
      
      Tool Name: #{tool.name}
      Description: #{tool.description}
      Execution Type: #{tool.execution_type}
      
      Code/Configuration:
      ```#{tool.execution_type == 'ruby_code' ? 'ruby' : 'json'}
      #{code_content}
      ```
      
      Assess the security risk. Look for:
      - Infinite loops or resource exhaustion
      - Unauthorized file system access (reading/writing sensitive files)
      - Network access to internal services (SSRF)
      - Command injection (e.g., system(), exec(), `backticks`)
      - Sensitive data exposure (logging secrets, returning full DB records)
      - Malicious intent
      
      Respond with a SINGLE JSON object in the following format:
      {
        "rating": "pass" | "review" | "fail",
        "reason": "A brief explanation of the rating."
      }
      
      Definitions:
      - "pass": Code is safe to run.
      - "review": Code has potential risks (e.g., extensive network calls, complex logic) and should be manually reviewed.
      - "fail": Code is definitely unsafe, malicious, or contains syntax errors that prevent safety analysis.
    PROMPT
  end

  def parse_response(content)
    # Strip markdown code blocks if present
    cleaned_content = content.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip
    
    begin
      JSON.parse(cleaned_content)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse security check response: #{content}"
      {
        "rating" => "review",
        "reason" => "Failed to parse security rating. Manual review required."
      }
    end
  end
end

