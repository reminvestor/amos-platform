# frozen_string_literal: true

module Factories
  # Generates test criteria for factory-created items using AI
  # Supports agents, tools, and integrations
  class TestCriteriaGenerator
    def initialize(user:, entity:)
      @user = user
      @entity = entity
      @bedrock_service = BedrockService.new
    end

    # Generate tests for any testable item
    def generate_tests_for(testable)
      case testable
      when AgentPlugin
        generate_agent_tests(testable)
      when ToolDefinition
        generate_tool_tests(testable)
      when Integration
        generate_integration_tests(testable)
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end

    private

    # ============================================
    # AGENT TEST GENERATION
    # ============================================
    
    def generate_agent_tests(agent)
      Rails.logger.info "🧪 Generating tests for agent: #{agent.name}"
      
      prompt = build_agent_test_prompt(agent)
      response = call_ai(prompt)
      tests = parse_test_response(response)
      
      create_test_criteria(agent, tests)
    end

    def build_agent_test_prompt(agent)
      system_prompt_content = agent.system_prompt.is_a?(Hash) ? agent.system_prompt['prompt'] : agent.system_prompt.to_s
      capabilities = agent.agent_capabilities.map(&:capability_name).join(', ')
      tools = agent.agent_tools.map(&:tool_name).join(', ')

      <<~PROMPT
        You are a QA Engineer creating acceptance tests for an AI Agent.

        ## Agent Details
        - **Name**: #{agent.name}
        - **Role**: #{agent.role}
        - **Description**: #{agent.description}
        - **Capabilities**: #{capabilities.presence || 'None specified'}
        - **Tools Available**: #{tools.presence || 'None'}
        - **System Prompt** (abbreviated):
        ```
        #{system_prompt_content.to_s.truncate(1000)}
        ```

        ## Your Task
        Generate 3-5 acceptance tests for this agent. Tests should verify:
        1. **Basic functionality** - Does the agent respond appropriately to its core use case?
        2. **Edge cases** - How does it handle unusual inputs?
        3. **Guardrails** - Does it stay within its defined role/constraints?

        ## Test Types Available
        - `semantic` - AI evaluates if output matches expected behavior (use for open-ended responses)
        - `contains` - Output must contain specific keywords/phrases
        - `regex` - Output must match a pattern

        ## Response Format
        Return a JSON array of test objects:
        ```json
        [
          {
            "name": "Basic greeting response",
            "description": "Agent should acknowledge user and offer help",
            "test_type": "semantic",
            "category": "functionality",
            "input_prompt": "Hello, I need your help",
            "expected_output": "Agent should greet the user warmly and ask how it can assist them",
            "is_required": true,
            "weight": 2
          },
          {
            "name": "Contains capability keywords",
            "description": "Response should mention agent's capabilities",
            "test_type": "contains",
            "category": "functionality", 
            "input_prompt": "What can you do?",
            "validation_rules": {
              "must_contain": ["help", "assist"]
            },
            "is_required": true,
            "weight": 1
          }
        ]
        ```

        Generate tests now. Return ONLY the JSON array, no other text.
      PROMPT
    end

    # ============================================
    # TOOL TEST GENERATION
    # ============================================
    
    def generate_tool_tests(tool)
      Rails.logger.info "🧪 Generating tests for tool: #{tool.name}"
      
      prompt = build_tool_test_prompt(tool)
      response = call_ai(prompt)
      tests = parse_test_response(response)
      
      create_test_criteria(tool, tests)
    end

    def build_tool_test_prompt(tool)
      <<~PROMPT
        You are a QA Engineer creating acceptance tests for an AI Tool.

        ## Tool Details
        - **Name**: #{tool.name}
        - **Description**: #{tool.description}
        - **Execution Type**: #{tool.execution_type}
        - **Parameters**: #{tool.parameters.to_json}
        #{tool.execution_type == 'ruby_code' ? "- **Ruby Code** (abbreviated):\n```ruby\n#{tool.ruby_code.to_s.truncate(500)}\n```" : ''}
        #{tool.execution_type == 'http_request' ? "- **HTTP Endpoint**: #{tool.http_endpoint}\n- **HTTP Method**: #{tool.http_method}" : ''}

        ## Your Task
        Generate 3-5 acceptance tests for this tool. Tests should verify:
        1. **Happy path** - Tool works with valid inputs
        2. **Input validation** - Tool handles invalid inputs gracefully
        3. **Output format** - Tool returns expected structure

        ## Test Types Available
        - `semantic` - AI evaluates if output matches expected behavior
        - `programmatic` - Exact value checks
        - `json_schema` - Validate output structure
        - `contains` - Output contains keywords
        - `http_status` - For HTTP tools, check status code

        ## Response Format
        Return a JSON array:
        ```json
        [
          {
            "name": "Valid input returns success",
            "description": "Tool should return success with valid parameters",
            "test_type": "programmatic",
            "category": "functionality",
            "input_data": {"param1": "value1"},
            "expected_values": {"success": true},
            "is_required": true,
            "weight": 2
          }
        ]
        ```

        Generate tests now. Return ONLY the JSON array.
      PROMPT
    end

    # ============================================
    # INTEGRATION TEST GENERATION
    # ============================================
    
    def generate_integration_tests(integration)
      Rails.logger.info "🧪 Generating tests for integration: #{integration.name}"
      
      prompt = build_integration_test_prompt(integration)
      response = call_ai(prompt)
      tests = parse_test_response(response)
      
      # Add standard HTTP connectivity test
      tests.unshift({
        'name' => 'API Connectivity',
        'description' => 'Integration can connect to the API endpoint',
        'test_type' => 'http_status',
        'category' => 'setup',
        'expected_status_code' => 200,
        'is_required' => true,
        'weight' => 3
      })
      
      create_test_criteria(integration, tests)
    end

    def build_integration_test_prompt(integration)
      operations = integration.integration_operations.limit(5).pluck(:name, :description)
      
      <<~PROMPT
        You are a QA Engineer creating acceptance tests for an API Integration.

        ## Integration Details
        - **Name**: #{integration.name}
        - **Description**: #{integration.description}
        - **Category**: #{integration.category}
        - **Auth Type**: #{integration.auth_type}
        - **Base URL**: #{integration.base_url}
        - **Operations Available**: #{operations.map { |n, d| "#{n}: #{d}" }.join('; ')}

        ## Your Task
        Generate 2-4 acceptance tests for this integration. Focus on:
        1. **Authentication** - Can we authenticate successfully?
        2. **Basic operation** - Can we perform a simple read operation?
        3. **Error handling** - Does it handle errors gracefully?

        ## Test Types Available
        - `http_status` - Check HTTP response status (use expected_status_code)
        - `semantic` - AI evaluates response quality
        - `json_schema` - Validate response structure

        ## Response Format
        Return a JSON array:
        ```json
        [
          {
            "name": "Authentication succeeds",
            "description": "Integration can authenticate with provided credentials",
            "test_type": "http_status",
            "category": "setup",
            "expected_status_code": 200,
            "is_required": true,
            "weight": 3
          }
        ]
        ```

        Generate tests now. Return ONLY the JSON array.
      PROMPT
    end

    # ============================================
    # HELPERS
    # ============================================
    
    def call_ai(prompt)
      messages = [{ role: "user", content: prompt }]
      
      @bedrock_service.send_message(
        nil,
        messages,
        model: "claude-sonnet-4-5",
        temperature: 0.3,
        json_mode: true
      )
    end

    def parse_test_response(response)
      # Clean up response
      cleaned = response.to_s
                       .gsub(/```json\n?/, '')
                       .gsub(/```\n?/, '')
                       .strip

      JSON.parse(cleaned)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse test criteria response: #{e.message}"
      Rails.logger.error "Response was: #{response.to_s.truncate(500)}"
      
      # Return a minimal default test
      [{
        'name' => 'Basic response check',
        'description' => 'Item should respond without errors',
        'test_type' => 'semantic',
        'category' => 'functionality',
        'input_prompt' => 'Test',
        'expected_output' => 'Should respond appropriately without errors',
        'is_required' => true,
        'weight' => 1
      }]
    end

    def create_test_criteria(testable, tests)
      created = []
      
      tests.each_with_index do |test, index|
        criteria = FactoryTestCriteria.create!(
          entity: @entity,
          user: @user,
          testable: testable,
          name: test['name'] || "Test #{index + 1}",
          description: test['description'],
          test_type: test['test_type'] || 'semantic',
          category: test['category'] || 'functionality',
          position: index,
          input_prompt: test['input_prompt'],
          input_data: test['input_data'] || {},
          expected_output: test['expected_output'],
          expected_values: test['expected_values'] || {},
          validation_rules: test['validation_rules'] || {},
          expected_status_code: test['expected_status_code'],
          expected_headers: test['expected_headers'] || {},
          is_required: test['is_required'] != false,
          weight: test['weight'] || 1
        )
        created << criteria
      end

      Rails.logger.info "✅ Created #{created.length} test criteria for #{testable.class.name} '#{testable.try(:name)}'"
      created
    rescue => e
      Rails.logger.error "Failed to create test criteria: #{e.message}"
      []
    end
  end
end

