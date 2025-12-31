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
      You are a Security Engineer reviewing tools for a multi-tenant SaaS platform.
      
      Review the following tool definition:
      
      Tool Name: #{tool.name}
      Description: #{tool.description}
      Execution Type: #{tool.execution_type}
      
      Code/Configuration:
      ```#{tool.execution_type == 'ruby_code' ? 'ruby' : 'json'}
      #{code_content}
      ```
      
      ## What We Care About (REAL THREATS)
      
      FAIL immediately for:
      - **Command injection:** system(), exec(), backticks, Open3, IO.popen
      - **Code injection:** eval(), instance_eval, class_eval, send with user input
      - **File system attacks:** Writing/deleting files, accessing /etc/passwd, ../ traversal
      - **SSRF to internal services:** Requests to localhost, 127.0.0.1, 10.x.x.x, 192.168.x.x, 172.16-31.x.x
      - **Credential theft:** Accessing ENV vars for secrets, Rails.application.credentials
      - **Database attacks:** Raw SQL, dropping tables, accessing other tenants' data
      - **Infinite loops:** while true, loop without break conditions
      
      ## What Is NORMAL and SAFE
      
      PASS for these common patterns:
      - **_context values are TRUSTED:** `_context[:entity]`, `_context[:user]` are SERVER-SIDE values set by the platform, NOT user input. Entity-scoped queries using _context[:entity] are the CORRECT way to enforce multi-tenancy.
      - **URL parameter interpolation:** `{{location}}` in URLs is EXPECTED and SAFE - we URL-encode these
      - **Calling external public APIs:** Weather APIs, search APIs, public data sources are fine
      - **Math calculations:** Loan calculators, ROI calculations, etc.
      - **Data transformation:** Parsing, formatting, converting data types
      - **String manipulation:** Building URLs, formatting output
      - **Standard CRUD operations:** Create, read, update, delete operations that filter by entity are safe multi-tenant patterns
      
      ## Rating Guidelines
      
      - "pass": Tool is safe. Normal API calls, calculations, data transforms.
      - "review": Unusual patterns that MIGHT be risky but aren't clearly malicious.
      - "fail": Definitely dangerous - command injection, file access, internal network access.
      
      Be PRACTICAL. Most tools calling external APIs with user parameters are FINE.
      Only flag things that could actually compromise our system or other users' data.
      
      Respond with a SINGLE JSON object:
      {
        "rating": "pass" | "review" | "fail",
        "reason": "Brief explanation"
      }
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

