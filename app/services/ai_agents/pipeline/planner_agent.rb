require 'yaml'

module AiAgents::Pipeline
  class PlannerAgent < BaseAgent
    # Minimum test cases required for a valid test spec
    MIN_TEST_CASES = 3

    def execute!
      log("Starting comprehensive implementation planning...")
      log("Using Claude Sonnet 4.5 for planning")

      inputs = agent_execution.inputs
      ticket_info = extract_ticket_info(inputs)

      # Read clarifications if available
      clarifications_data = read_clarifications
      if clarifications_data
        log("Loaded clarifications from previous agent")
        ticket_info[:clarifications] = clarifications_data
      end

      # Generate implementation plan
      log("Generating implementation plan...")
      plan_result = generate_implementation_plan(ticket_info)

      unless plan_result[:success]
        raise "Plan generation failed: #{plan_result[:error]}"
      end

      plan_content = plan_result[:plan]
      log("Plan generated (#{plan_content.bytesize} bytes)")

      # Generate test specification
      log("Generating test specification...")
      test_spec_result = generate_test_specification(ticket_info, plan_content)

      unless test_spec_result[:success]
        raise "Test spec generation failed: #{test_spec_result[:error]}"
      end

      test_spec = test_spec_result[:spec]
      log("Test spec generated with #{test_spec['test_cases']&.length || 0} test cases")

      # Validate test specification
      log("Validating test specification...")
      validation_result = validate_test_spec(test_spec)

      unless validation_result[:valid]
        raise "Test spec validation failed: #{validation_result[:errors].join(', ')}"
      end

      # Generate architecture diagram
      log("Generating architecture diagram...")
      architecture_result = generate_architecture_diagram(ticket_info, plan_content)

      if architecture_result[:success]
        save_artifact('architecture_diagram', 'architecture.mermaid', architecture_result[:diagram])
        log("Architecture diagram saved")
      else
        log("Warning: Architecture diagram generation failed: #{architecture_result[:error]}")
      end

      # Save artifacts
      log("Saving plan artifacts...")
      save_artifact('plan', 'plan.md', plan_content)
      save_artifact('test_spec', 'test_spec.yaml', test_spec.to_yaml)

      # Complete agent execution
      agent_execution.complete!(
        plan_generated: true,
        test_cases_count: test_spec['test_cases'].length,
        files_to_create: extract_file_list(plan_content, 'create'),
        files_to_modify: extract_file_list(plan_content, 'modify'),
        implementation_steps_count: count_implementation_steps(plan_content),
        has_architecture_diagram: architecture_result[:success]
      )

      log("Planning complete!")
      log("- Test cases: #{test_spec['test_cases'].length}")
      log("- Implementation steps: #{count_implementation_steps(plan_content)}")
    end

    private

    # Extract ticket information from inputs
    def extract_ticket_info(inputs)
      {
        ticket_id: inputs['ticket_id'],
        title: inputs['ticket_title'],
        description: inputs['ticket_description'],
        priority: inputs['priority'] || 'medium',
        ticket_system: inputs['ticket_system'],
        repository: inputs['repository']
      }
    end

    # Read clarifications from previous agent (ClarifierAgent)
    def read_clarifications
      clarification_artifact = get_artifact('clarifications')
      return nil unless clarification_artifact

      content = clarification_artifact.get_content || clarification_artifact.content
      return nil unless content

      begin
        JSON.parse(content)
      rescue JSON::ParserError => e
        log("Warning: Failed to parse clarifications: #{e.message}")
        nil
      end
    end

    # Generate comprehensive implementation plan
    def generate_implementation_plan(ticket_info)
      system_prompt = build_plan_system_prompt
      user_message = build_plan_user_message(ticket_info)

      result = call_claude(
        system_prompt,
        user_message,
        model: 'claude-sonnet-4-5',
        max_tokens: 8000,
        temperature: 0.5
      )

      return { success: false, error: result[:error] } unless result[:success]

      {
        success: true,
        plan: result[:content]
      }
    end

    def build_plan_system_prompt
      <<~PROMPT
        You are an expert software architect and technical lead creating detailed implementation plans
        for an AI development pipeline. Your plans guide autonomous AI agents to implement features.

        Your implementation plan must be comprehensive, precise, and actionable.

        ## Plan Structure

        Create a plan with the following sections:

        ### 1. Executive Summary
        - Brief overview (2-3 sentences)
        - Key objectives
        - Success criteria

        ### 2. Technical Approach
        - Architecture overview
        - Design patterns to use
        - Technology stack
        - Integration points

        ### 3. Implementation Steps
        List specific, ordered steps with:
        - Step number and description
        - File path to create/modify
        - Key code changes
        - Dependencies on previous steps

        Format:
        **Step 1**: Description
        - **Action**: Create/Modify
        - **File**: `path/to/file.rb`
        - **Details**: What to implement

        ### 4. Files to Create/Modify
        Clear list with categorization:

        **New Files**:
        - `app/models/new_model.rb` - Description
        - `app/controllers/new_controller.rb` - Description

        **Modified Files**:
        - `config/routes.rb` - Add new routes
        - `app/models/existing.rb` - Add new methods

        ### 5. Database Changes
        - Migrations needed
        - Schema changes
        - Indexing requirements

        ### 6. Testing Strategy
        - Unit tests required
        - Integration tests required
        - Edge cases to cover
        - Test data needed

        ### 7. Security Considerations
        - Authentication/authorization
        - Input validation
        - Secrets management
        - Potential vulnerabilities

        ### 8. Performance Considerations
        - Scalability concerns
        - Caching strategy
        - Database optimization
        - Background job usage

        ### 9. Acceptance Criteria
        Clear, testable criteria:
        - [ ] Criterion 1
        - [ ] Criterion 2
        - [ ] Criterion 3

        ### 10. Dependencies & Risks
        - External dependencies
        - Breaking changes
        - Rollback strategy
        - Known risks

        ## Guidelines
        - Be specific about file paths (use actual Rails/framework conventions)
        - Include error handling approach
        - Specify exact gem/package versions if new dependencies
        - Consider backward compatibility
        - Plan for monitoring and observability

        Write in markdown format with clear sections.
      PROMPT
    end

    def build_plan_user_message(ticket_info)
      clarifications_section = ""
      if ticket_info[:clarifications]
        clarifications_section = <<~CLARIFICATIONS

          ## Clarifications
          The following clarifications were gathered:

          **Summary**: #{ticket_info[:clarifications]['summary']}

          **Requirements**:
          #{ticket_info[:clarifications]['requirements']&.map { |r| "- #{r}" }&.join("\n")}

        CLARIFICATIONS
      end

      <<~MESSAGE
        Create a detailed implementation plan for the following ticket:

        ## Ticket Information
        - **ID**: #{ticket_info[:ticket_id]}
        - **Title**: #{ticket_info[:title]}
        - **Priority**: #{ticket_info[:priority]&.upcase}
        - **System**: #{ticket_info[:ticket_system] || 'Manual'}
        - **Repository**: #{ticket_info[:repository] || 'Not specified'}

        ## Description
        #{ticket_info[:description]}

        #{clarifications_section}

        ## Context
        This is a Ruby on Rails 8 application with:
        - Turbo/Stimulus frontend
        - PostgreSQL database
        - Background jobs via SolidQueue
        - AWS Bedrock for AI (Claude models)
        - Bootstrap 5 UI

        Generate a comprehensive implementation plan following the structure specified.
        Be thorough but concise. Focus on actionable steps.
      MESSAGE
    end

    # Generate test specification in YAML format
    def generate_test_specification(ticket_info, plan_content)
      system_prompt = build_test_spec_system_prompt
      user_message = build_test_spec_user_message(ticket_info, plan_content)

      result = call_claude(
        system_prompt,
        user_message,
        model: 'claude-sonnet-4-5',
        max_tokens: 4000,
        temperature: 0.3
      )

      return { success: false, error: result[:error] } unless result[:success]

      # Parse YAML from response
      begin
        # Extract YAML from markdown code blocks if present
        yaml_content = result[:content]
        if yaml_content.include?('```yaml')
          yaml_content = yaml_content.match(/```yaml\n(.*?)\n```/m)[1]
        elsif yaml_content.include?('```')
          yaml_content = yaml_content.match(/```\n(.*?)\n```/m)[1]
        end

        spec = YAML.safe_load(yaml_content, permitted_classes: [Symbol])

        {
          success: true,
          spec: spec
        }
      rescue => e
        log("Failed to parse test spec YAML: #{e.message}")
        # Return a minimal valid spec
        {
          success: true,
          spec: {
            'ticket_id' => ticket_info[:ticket_id],
            'test_cases' => [
              {
                'name' => 'Basic functionality test',
                'type' => 'unit',
                'description' => 'Verify basic functionality works'
              },
              {
                'name' => 'Error handling test',
                'type' => 'unit',
                'description' => 'Verify error handling'
              },
              {
                'name' => 'Integration test',
                'type' => 'integration',
                'description' => 'Verify integration with other components'
              }
            ]
          }
        }
      end
    end

    def build_test_spec_system_prompt
      <<~PROMPT
        You are a QA engineer creating comprehensive test specifications for automated testing.

        Generate a test specification in YAML format with the following structure:

        ```yaml
        ticket_id: TICKET-123
        feature: Feature name
        test_strategy: Brief testing strategy

        test_cases:
          - name: Test case name
            type: unit|integration|e2e
            priority: high|medium|low
            description: What this test verifies
            file_path: spec/path/to/test_spec.rb
            test_steps:
              - Arrange: Setup test data
              - Act: Execute action
              - Assert: Verify results
            expected_result: What should happen
            edge_cases:
              - Edge case 1
              - Edge case 2

          - name: Another test case
            # ... same structure

        coverage_requirements:
          minimum_percentage: 80
          critical_paths:
            - Path 1
            - Path 2

        test_data:
          fixtures:
            - Fixture description
          mocks:
            - Mock description
        ```

        ## Requirements:
        - Include at least 3 test cases (unit, integration, edge cases)
        - Cover happy path, error cases, and edge cases
        - Specify exact file paths for test files
        - Include clear assertions
        - Consider security testing where relevant

        Respond with ONLY the YAML content (you may wrap in ```yaml code block).
      PROMPT
    end

    def build_test_spec_user_message(ticket_info, plan_content)
      <<~MESSAGE
        Create a test specification for:

        **Ticket**: #{ticket_info[:ticket_id]} - #{ticket_info[:title]}

        **Implementation Plan Summary**:
        #{plan_content.lines.first(30).join}
        #{plan_content.lines.count > 30 ? "\n... (full plan available)" : ""}

        Generate comprehensive test specification in YAML format.
        Include unit tests, integration tests, and edge case testing.
      MESSAGE
    end

    # Generate architecture diagram in Mermaid format
    def generate_architecture_diagram(ticket_info, plan_content)
      system_prompt = <<~PROMPT
        You are a technical architect creating system architecture diagrams.

        Generate a Mermaid diagram showing the architecture for this implementation.

        Use appropriate Mermaid syntax:
        - `graph TD` or `graph LR` for flowcharts
        - `sequenceDiagram` for sequence diagrams
        - `classDiagram` for class relationships
        - `erDiagram` for database relationships

        Include:
        - Key components/classes
        - Relationships and data flow
        - External dependencies
        - Database tables if applicable

        Respond with ONLY the Mermaid diagram code (you may wrap in ```mermaid code block).
      PROMPT

      user_message = <<~MESSAGE
        Create an architecture diagram for:

        **Feature**: #{ticket_info[:title]}

        **Implementation Summary**:
        #{plan_content.lines.first(20).join}

        Generate a clear, well-structured Mermaid diagram.
      MESSAGE

      result = call_claude(
        system_prompt,
        user_message,
        model: 'claude-sonnet-4-5',
        max_tokens: 2000,
        temperature: 0.3
      )

      return { success: false, error: result[:error] } unless result[:success]

      # Extract Mermaid from code blocks if present
      diagram = result[:content]
      if diagram.include?('```mermaid')
        diagram = diagram.match(/```mermaid\n(.*?)\n```/m)[1]
      elsif diagram.include?('```')
        diagram = diagram.match(/```\n(.*?)\n```/m)[1]
      end

      {
        success: true,
        diagram: diagram
      }
    rescue => e
      { success: false, error: e.message }
    end

    # Validate test specification
    def validate_test_spec(spec)
      errors = []

      # Check required fields
      unless spec.is_a?(Hash)
        errors << "Test spec must be a hash/object"
        return { valid: false, errors: errors }
      end

      unless spec['test_cases'].is_a?(Array)
        errors << "Test spec must include 'test_cases' array"
        return { valid: false, errors: errors }
      end

      # Check minimum test cases
      if spec['test_cases'].length < MIN_TEST_CASES
        errors << "Test spec must include at least #{MIN_TEST_CASES} test cases (found #{spec['test_cases'].length})"
      end

      # Validate each test case
      spec['test_cases'].each_with_index do |test_case, index|
        unless test_case.is_a?(Hash)
          errors << "Test case #{index + 1} must be a hash/object"
          next
        end

        unless test_case['name']
          errors << "Test case #{index + 1} missing 'name' field"
        end

        unless test_case['type']
          errors << "Test case #{index + 1} missing 'type' field"
        end

        unless test_case['description']
          errors << "Test case #{index + 1} missing 'description' field"
        end
      end

      {
        valid: errors.empty?,
        errors: errors
      }
    end

    # Extract file list from plan (files to create or modify)
    def extract_file_list(plan_content, action_type)
      files = []

      # Look for file patterns in the plan
      case action_type
      when 'create'
        # Match patterns like "New Files:" section or "Create: path/to/file"
        plan_content.scan(/(?:New Files?|Create).*?`([^`]+\.[a-z]+)`/i) do |match|
          files << match[0]
        end
      when 'modify'
        # Match patterns like "Modified Files:" section or "Modify: path/to/file"
        plan_content.scan(/(?:Modified Files?|Modify).*?`([^`]+\.[a-z]+)`/i) do |match|
          files << match[0]
        end
      end

      files.uniq
    end

    # Count implementation steps in the plan
    def count_implementation_steps(plan_content)
      # Count lines that look like step markers
      steps = 0

      # Match patterns like "**Step 1**:" or "1." at start of line
      plan_content.scan(/^\*\*Step \d+\*\*:|^\d+\./m) do
        steps += 1
      end

      # Fallback: count "Implementation Steps" section items
      if steps == 0
        implementation_section = plan_content.match(/## Implementation Steps.*?(?=##|\z)/m)
        if implementation_section
          steps = implementation_section[0].scan(/^[-*]\s/).length
        end
      end

      steps
    end
  end
end
