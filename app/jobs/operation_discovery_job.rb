class OperationDiscoveryJob < ApplicationJob
  queue_as :default

  def perform(integration_id, user_id, existing_operations: [], user_specification: nil)
    @integration = Integration.find(integration_id)
    @user = User.find(user_id)
    @existing_operations = existing_operations
    @user_spec = user_specification
    
    Rails.logger.info "🔍 Starting operation discovery for #{@integration.name}"
    
    # Build the AI prompt
    prompt = build_discovery_prompt
    
    # Call AI to discover operations
    discovered_operations = call_ai_for_discovery(prompt)
    
    # Notify user of results
    notify_user(discovered_operations)
    
    Rails.logger.info "✅ Operation discovery completed for #{@integration.name}: #{discovered_operations.count} operations found"
  rescue => e
    Rails.logger.error "❌ Operation discovery failed: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    
    # Notify user of failure
    notify_user_of_error(e.message)
  end
  
  private
  
  def build_discovery_prompt
    prompt = <<~PROMPT
      You are an API integration expert. Your task is to discover new useful operations for the #{@integration.name} API integration.
      
      **Integration Details:**
      - Name: #{@integration.name}
      - Base URL: #{@integration.api_base_url}
      - Documentation: #{@integration.documentation_url}
      - Category: #{@integration.category}
      - Auth Type: #{@integration.auth_type}
      
      **Existing Operations (#{@existing_operations.count}) - USE THESE AS TEMPLATES:**
      #{format_existing_operations_detailed}
      
      #{user_specification_section}
      
      **Your Task:**
      1. **Research Phase:**
         - Search the web for #{@integration.name} API documentation
         - Look for OpenAPI/Swagger specifications if available
         - Find official API reference, developer docs, and code examples
         - Review community tutorials and integration guides
      
      2. **Analysis Phase:**
         - Study the EXISTING operations above to understand:
           * URL structure and patterns (path templates, parameters)
           * How authentication is handled
           * Naming conventions (operation_id format)
           * Schema patterns (request/response structures)
           * Pagination strategies used
         - Identify gaps: What common operations are missing?
      
      3. **Discovery Phase:**
         - Suggest 5-10 of the MOST USEFUL operations not yet implemented
         - Prioritize commonly used endpoints for business automation
         - Focus on CRUD operations (Create, Read, Update, Delete/List)
         - Include operations that complement existing ones
      
      **Requirements for each operation (MATCH THE PATTERNS FROM EXISTING OPERATIONS):**
      1. `operation_id`: Format as `#{@integration.slug}.operation_name` (lowercase, underscores)
      2. `name`: Human-readable title (e.g., "List Customers", "Create Invoice")
      3. `description`: Clear, concise explanation
      4. `http_method`: GET, POST, PUT, PATCH, or DELETE
      5. `path_template`: Match the style of existing operations
         - Use {paramName} for path parameters (match existing naming: camelCase or snake_case)
         - Keep version prefixes consistent (/v1, /v3, etc.)
      6. `request_schema`: JSON Schema for parameters
         - Study existing schemas for format/structure
         - Include "type", "properties", "required" arrays
         - Add helpful "description" fields
      7. `response_schema`: Expected response structure
         - Match patterns from existing operations
      8. `pagination_strategy`: "cursor", "offset", "page", or "no_pagination"
         - Use the same strategy as similar existing operations
      9. `is_idempotent`: true for GET/PUT, false for POST
      10. `requires_confirmation`: true only for DELETE or risky operations
      11. `max_limit`: For list operations, match existing limits (typically 100)
      
      **Critical: Validate Your Suggestions**
      - Double-check endpoint paths against official API docs
      - Ensure parameter names match the actual API
      - Verify HTTP methods are correct
      - Confirm pagination strategies match the API's actual behavior
      
      **Response Format:**
      Return ONLY a valid JSON array. Example:
      ```json
      [
        {
          "operation_id": "#{@integration.slug}.list_customers",
          "name": "List Customers",
          "description": "Retrieve a paginated list of customers",
          "http_method": "GET",
          "path_template": "/v1/customers",
          "request_schema": {
            "type": "object",
            "properties": {
              "limit": {"type": "integer", "minimum": 1, "maximum": 100, "default": 10},
              "starting_after": {"type": "string", "description": "Cursor for pagination"}
            }
          },
          "response_schema": {
            "type": "object",
            "properties": {
              "data": {"type": "array"},
              "has_more": {"type": "boolean"}
            }
          },
          "pagination_strategy": "cursor",
          "is_idempotent": true,
          "requires_confirmation": false,
          "max_limit": 100
        }
      ]
      ```
      
      Remember: Quality over quantity. Only suggest operations you're confident are correct based on real API documentation.
    PROMPT
    
    prompt
  end
  
  def format_existing_operations_detailed
    if @existing_operations.empty?
      "None - this is a new integration! You'll need to research the API from scratch."
    else
      @existing_operations.map do |op_id, name, path|
        # Get full operation details for better template
        operation = @integration.integration_operations.find_by(operation_id: op_id)
        if operation
          <<~OP_DETAIL
            **#{op_id}** - #{name}
            - Path: `#{path}`
            - Method: #{operation.http_method}
            - Pagination: #{operation.pagination_strategy}
            - Idempotent: #{operation.is_idempotent}
            - Request Schema: #{operation.request_schema.present? ? 'Defined' : 'None'}
            - Max Limit: #{operation.max_limit || 'N/A'}
          OP_DETAIL
        else
          "- #{op_id}: #{name} (#{path})"
        end
      end.join("\n")
    end
  end
  
  def user_specification_section
    return "" unless @user_spec.present?
    
    <<~SPEC
      **User-Specified Operations/Endpoints to Include:**
      #{@user_spec}
      
      Please prioritize these user-specified operations in your suggestions.
    SPEC
  end
  
  def call_ai_for_discovery(prompt)
    # Use Bedrock Converse API with Claude Sonnet 3.5 (on-demand available)
    client = Aws::BedrockRuntime::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
    
    response = client.converse(
      model_id: "us.anthropic.claude-sonnet-4-20250514-v1:0", # Use inference profile for on-demand
      messages: [
        {
          role: "user",
          content: [{ text: prompt }]
        }
      ],
      inference_config: {
        max_tokens: 4000,
        temperature: 0.3 # Lower temperature for more focused, structured output
      }
    )
    
    # Extract the text response
    ai_response = response.output.message.content.first.text
    
    # Parse JSON from response (strip markdown code blocks if present)
    json_text = ai_response.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip
    operations = JSON.parse(json_text)
    
    # Validate and clean up operations
    operations.map { |op| validate_and_clean_operation(op) }.compact
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse AI response as JSON: #{e.message}"
    Rails.logger.error "AI Response: #{ai_response}"
    []
  end
  
  def validate_and_clean_operation(op)
    required_fields = %w[operation_id name http_method path_template]
    return nil unless required_fields.all? { |field| op[field].present? }
    
    # Ensure operation_id starts with integration slug
    unless op["operation_id"].start_with?("#{@integration.slug}.")
      op["operation_id"] = "#{@integration.slug}.#{op["operation_id"]}"
    end
    
    # Set defaults
    op["pagination_strategy"] ||= "no_pagination"
    op["is_idempotent"] ||= (op["http_method"] == "GET")
    op["requires_confirmation"] ||= %w[DELETE].include?(op["http_method"])
    op["is_enabled"] ||= true
    
    op
  end
  
  def notify_user(discovered_operations)
    if discovered_operations.empty?
      # No operations found - just log it
      Rails.logger.info "No new operations discovered for #{@integration.name}"
    else
      # Create operations directly (disabled by default for review)
      created_count = 0
      discovered_operations.each do |op_data|
        begin
          operation = @integration.integration_operations.create!(
            operation_id: op_data["operation_id"],
            name: op_data["name"],
            description: op_data["description"],
            http_method: op_data["http_method"],
            path_template: op_data["path_template"],
            request_schema: op_data["request_schema"] || {},
            response_schema: op_data["response_schema"] || {},
            pagination_strategy: op_data["pagination_strategy"],
            is_idempotent: op_data["is_idempotent"],
            requires_confirmation: op_data["requires_confirmation"],
            max_limit: op_data["max_limit"],
            is_enabled: false, # Disabled by default for admin review
            documentation: "Auto-discovered by AI on #{Time.current.strftime('%Y-%m-%d')}"
          )
          created_count += 1
          Rails.logger.info "✅ Created operation: #{operation.operation_id}"
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.warn "⚠️ Skipped duplicate operation: #{op_data['operation_id']}"
        end
      end
      
      Rails.logger.info "✅ Created #{created_count} new operations for #{@integration.name}"
    end
  end
  
  def notify_user_of_error(error_message)
    Rails.logger.error "❌ Operation discovery failed for #{@integration.name}: #{error_message}"
  end
end

