# frozen_string_literal: true

module Factories
  # Runs tests for factory-created items
  # Supports both programmatic (exact) and semantic (AI-evaluated) tests
  class FactoryTestRunner
    MAX_ATTEMPTS = 3
    SEMANTIC_PASS_THRESHOLD = 0.7  # 70% similarity to pass semantic tests

    def initialize(session: nil, user: nil, entity: nil)
      @session = session
      @user = user || session&.user
      @entity = entity || session&.entity
      @bedrock_service = BedrockService.new
    end

    # Run all tests for a testable item with retry logic
    def run_all_tests(testable, max_attempts: MAX_ATTEMPTS)
      criteria = FactoryTestCriteria.for_testable(testable).active.by_position
      
      if criteria.empty?
        Rails.logger.info "⚠️ No test criteria found for #{testable.class.name} #{testable.id}"
        return { success: true, message: "No tests defined", session: nil }
      end

      attempt = 1
      session = nil
      
      while attempt <= max_attempts
        Rails.logger.info "🧪 Test attempt #{attempt}/#{max_attempts} for #{testable.class.name} '#{testable.try(:name)}'"
        
        # Create test session
        session = FactoryTestSession.create!(
          entity: @entity,
          user: @user,
          testable: testable,
          attempt_number: attempt,
          max_attempts: max_attempts
        )
        @session = session
        session.start!

        # Run each test
        all_passed = true
        criteria.each do |test_criteria|
          run = run_single_test(test_criteria, attempt_number: attempt)
          
          if !run.passed && test_criteria.is_required
            all_passed = false
          end
        end

        # Complete session
        session.complete!

        if session.all_required_passed?
          Rails.logger.info "✅ All required tests passed on attempt #{attempt}"
          
          # Get AI analysis of results
          analysis = analyze_results(session)
          
          return {
            success: true,
            message: "All required tests passed",
            session: session,
            report: session.detailed_report,
            analysis: analysis
          }
        end

        # If not passed and can retry, get AI feedback for fixes
        if attempt < max_attempts
          feedback = generate_fix_feedback(session)
          apply_fixes_to_testable(testable, feedback) if feedback[:fixes].present?
        end

        attempt += 1
      end

      # Max attempts reached - deliver in current state
      Rails.logger.warn "⚠️ Max attempts (#{max_attempts}) reached for #{testable.class.name} '#{testable.try(:name)}'"
      
      # Get AI analysis of results (helps user understand what's wrong)
      analysis = analyze_results(session)
      
      session.deliver!(notes: "Delivered after #{max_attempts} attempts. #{analysis['summary']}")

      {
        success: false,
        message: "Delivered after #{max_attempts} attempts with some failing tests",
        session: session,
        report: session.detailed_report,
        analysis: analysis
      }
    end

    # Get AI analysis of test results
    def analyze_results(session)
      analyst = Factories::TestResultsAnalyst.new
      analyst.analyze(session)
    rescue => e
      Rails.logger.error "Analysis failed: #{e.message}"
      { 'summary' => 'Analysis unavailable', 'recommendation' => { 'action' => 'review' } }
    end

    # Run a single test
    def run_single_test(test_criteria, attempt_number: 1)
      run = FactoryTestRun.create!(
        factory_test_criteria: test_criteria,
        factory_test_session: @session,
        entity: @entity,
        user: @user,
        attempt_number: attempt_number
      )

      run.start!
      start_time = Time.current

      begin
        result = execute_test(test_criteria)
        duration = ((Time.current - start_time) * 1000).to_i

        if result[:passed]
          run.pass!(
            output: result[:actual_output],
            values: result[:actual_values] || {},
            score: result[:similarity_score],
            evaluation: result[:ai_evaluation],
            duration: duration
          )
        else
          run.fail!(
            output: result[:actual_output],
            error: result[:error],
            diff: result[:diff],
            score: result[:similarity_score],
            evaluation: result[:ai_evaluation],
            feedback: result[:feedback],
            fix: result[:fix_suggestion],
            duration: duration
          )
        end

      rescue => e
        Rails.logger.error "Test execution error: #{e.message}"
        run.error!(e.message)
      end

      run
    end

    private

    # Execute a test based on its type
    def execute_test(criteria)
      case criteria.test_type
      when 'semantic'
        execute_semantic_test(criteria)
      when 'programmatic'
        execute_programmatic_test(criteria)
      when 'http_status'
        execute_http_status_test(criteria)
      when 'json_schema'
        execute_json_schema_test(criteria)
      when 'regex'
        execute_regex_test(criteria)
      when 'contains'
        execute_contains_test(criteria)
      else
        { passed: false, error: "Unknown test type: #{criteria.test_type}" }
      end
    end

    # ============================================
    # SEMANTIC TEST (AI-evaluated)
    # ============================================
    
    def execute_semantic_test(criteria)
      testable = criteria.testable
      
      # Get actual output from the testable
      actual_output = get_testable_output(testable, criteria.input_prompt, criteria.input_data)
      
      # Use AI to evaluate
      evaluation = evaluate_semantically(
        expected: criteria.expected_output,
        actual: actual_output,
        context: criteria.description
      )

      passed = evaluation[:score] >= SEMANTIC_PASS_THRESHOLD

      {
        passed: passed,
        actual_output: actual_output,
        similarity_score: evaluation[:score],
        ai_evaluation: evaluation[:explanation],
        feedback: passed ? nil : evaluation[:feedback],
        fix_suggestion: passed ? nil : evaluation[:fix_suggestion]
      }
    end

    def evaluate_semantically(expected:, actual:, context:)
      prompt = <<~PROMPT
        You are evaluating if an AI output meets the expected behavior.

        ## Context
        #{context}

        ## Expected Behavior
        #{expected}

        ## Actual Output
        #{actual}

        ## Your Task
        Evaluate how well the actual output matches the expected behavior.

        Return a JSON object:
        ```json
        {
          "score": 0.85,  // 0.0 to 1.0 (1.0 = perfect match)
          "explanation": "Brief explanation of why this score",
          "feedback": "What specifically needs improvement (if score < 0.7)",
          "fix_suggestion": "Specific suggestion to fix the issue"
        }
        ```

        Return ONLY the JSON object.
      PROMPT

      response = @bedrock_service.send_message(
        nil,
        [{ role: "user", content: prompt }],
        model: "qwen3-next-80b",
        temperature: 0.1,
        json_mode: true
      )

      parsed = JSON.parse(response.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip)
      
      {
        score: parsed['score'].to_f.clamp(0.0, 1.0),
        explanation: parsed['explanation'],
        feedback: parsed['feedback'],
        fix_suggestion: parsed['fix_suggestion']
      }
    rescue => e
      Rails.logger.error "Semantic evaluation failed: #{e.message}"
      { score: 0.5, explanation: "Evaluation failed: #{e.message}", feedback: nil, fix_suggestion: nil }
    end

    # ============================================
    # PROGRAMMATIC TESTS
    # ============================================
    
    def execute_programmatic_test(criteria)
      testable = criteria.testable
      actual_output = get_testable_output(testable, criteria.input_prompt, criteria.input_data)
      
      # Parse actual output if it's JSON
      actual_values = if actual_output.is_a?(String) && actual_output.strip.start_with?('{')
        JSON.parse(actual_output) rescue { 'raw' => actual_output }
      elsif actual_output.is_a?(Hash)
        actual_output
      else
        { 'raw' => actual_output }
      end

      # Check expected values
      expected = criteria.expected_values
      passed = true
      diff = []

      expected.each do |key, expected_value|
        actual_value = actual_values[key] || actual_values[key.to_s]
        
        if actual_value != expected_value
          passed = false
          diff << "#{key}: expected '#{expected_value}', got '#{actual_value}'"
        end
      end

      {
        passed: passed,
        actual_output: actual_output,
        actual_values: actual_values,
        diff: diff.join('; '),
        error: passed ? nil : "Value mismatch: #{diff.join('; ')}"
      }
    end

    def execute_http_status_test(criteria)
      testable = criteria.testable
      
      # For integrations, make an actual HTTP request
      unless testable.is_a?(Integration)
        return { passed: false, error: "HTTP status test only works with Integrations" }
      end

      begin
        # Try to make a simple request to the integration
        response = test_integration_connectivity(testable)
        
        actual_status = response[:status]
        expected_status = criteria.expected_status_code || 200
        passed = actual_status == expected_status

        {
          passed: passed,
          actual_output: response[:body],
          actual_status_code: actual_status,
          response_time_ms: response[:time_ms],
          error: passed ? nil : "Expected status #{expected_status}, got #{actual_status}"
        }
      rescue => e
        { passed: false, error: "HTTP request failed: #{e.message}" }
      end
    end

    def execute_json_schema_test(criteria)
      testable = criteria.testable
      actual_output = get_testable_output(testable, criteria.input_prompt, criteria.input_data)

      schema = criteria.validation_rules['schema']
      return { passed: false, error: "No schema defined" } unless schema

      begin
        actual_json = JSON.parse(actual_output.to_s)
        # Simple schema validation (in production, use json-schema gem)
        passed = validate_json_schema(actual_json, schema)
        
        { passed: passed, actual_output: actual_output, error: passed ? nil : "Schema validation failed" }
      rescue JSON::ParserError
        { passed: false, actual_output: actual_output, error: "Output is not valid JSON" }
      end
    end

    def execute_regex_test(criteria)
      testable = criteria.testable
      actual_output = get_testable_output(testable, criteria.input_prompt, criteria.input_data)

      pattern = criteria.validation_rules['pattern']
      return { passed: false, error: "No regex pattern defined" } unless pattern

      begin
        regex = Regexp.new(pattern)
        passed = actual_output.to_s.match?(regex)
        
        { passed: passed, actual_output: actual_output, error: passed ? nil : "Output does not match pattern: #{pattern}" }
      rescue RegexpError => e
        { passed: false, error: "Invalid regex: #{e.message}" }
      end
    end

    def execute_contains_test(criteria)
      testable = criteria.testable
      actual_output = get_testable_output(testable, criteria.input_prompt, criteria.input_data)

      must_contain = criteria.validation_rules['must_contain'] || []
      must_not_contain = criteria.validation_rules['must_not_contain'] || []

      output_lower = actual_output.to_s.downcase
      missing = []
      forbidden = []

      must_contain.each do |term|
        missing << term unless output_lower.include?(term.to_s.downcase)
      end

      must_not_contain.each do |term|
        forbidden << term if output_lower.include?(term.to_s.downcase)
      end

      passed = missing.empty? && forbidden.empty?
      errors = []
      errors << "Missing: #{missing.join(', ')}" if missing.any?
      errors << "Should not contain: #{forbidden.join(', ')}" if forbidden.any?

      { passed: passed, actual_output: actual_output, error: errors.join('; ').presence }
    end

    # ============================================
    # HELPERS
    # ============================================
    
    def get_testable_output(testable, input_prompt, input_data)
      case testable
      when AgentPlugin
        run_agent_test(testable, input_prompt)
      when ToolDefinition
        run_tool_test(testable, input_data)
      when Integration
        run_integration_test(testable, input_data)
      else
        "Unknown testable type"
      end
    end

    def run_agent_test(agent, prompt)
      return "No prompt provided" if prompt.blank?

      # Create a test execution
      executor = agent.instantiate(
        entity: @entity,
        user: @user,
        test_mode: true
      )

      result = executor.run(prompt, { test_mode: true })
      
      # Extract the response content
      if result.is_a?(Hash)
        result['content'] || result[:content] || result['message'] || result[:message] || result.to_s
      else
        result.to_s
      end
    rescue => e
      "Error: #{e.message}"
    end

    def run_tool_test(tool, input_data)
      # Execute the tool with test data
      catalog = Tools::ToolCatalog.instance
      
      result = catalog.execute_tool(
        tool.name,
        input_data,
        user: @user,
        entity: @entity,
        context: { test_mode: true }
      )

      result.to_json
    rescue => e
      "Error: #{e.message}"
    end

    def run_integration_test(integration, input_data)
      # Make a test request to the integration
      response = test_integration_connectivity(integration)
      response.to_json
    rescue => e
      "Error: #{e.message}"
    end

    def test_integration_connectivity(integration)
      # Simple connectivity test
      start_time = Time.current
      
      # Use the integration's base URL for a simple check
      uri = URI.parse(integration.base_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
      
      {
        status: response.code.to_i,
        body: response.body.to_s.truncate(500),
        time_ms: ((Time.current - start_time) * 1000).to_i
      }
    rescue => e
      { status: 0, body: "Connection failed: #{e.message}", time_ms: 0 }
    end

    def validate_json_schema(json, schema)
      # Simple schema validation (required fields, types)
      return true unless schema.is_a?(Hash)
      
      required = schema['required'] || []
      required.all? { |field| json.key?(field) || json.key?(field.to_s) }
    end

    def generate_fix_feedback(session)
      failed_runs = session.factory_test_runs.failed
      return { fixes: [] } if failed_runs.empty?

      feedback_parts = failed_runs.map do |run|
        "Test '#{run.criteria_name}' failed: #{run.error_message || run.ai_evaluation}"
      end

      prompt = <<~PROMPT
        The following tests failed for a #{session.testable_type}:

        #{feedback_parts.join("\n\n")}

        Provide specific fixes. Return JSON:
        ```json
        {
          "summary": "Brief summary of issues",
          "fixes": [
            {
              "test_name": "Test name",
              "issue": "What's wrong",
              "fix": "Specific fix to apply"
            }
          ]
        }
        ```
      PROMPT

      response = @bedrock_service.send_message(
        nil,
        [{ role: "user", content: prompt }],
        model: "qwen3-next-80b",
        temperature: 0.2,
        json_mode: true
      )

      JSON.parse(response.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip)
    rescue => e
      Rails.logger.error "Failed to generate fix feedback: #{e.message}"
      { summary: "Could not generate fixes", fixes: [] }
    end

    def apply_fixes_to_testable(testable, feedback)
      # This is where the AI would attempt to fix the testable
      # For now, log the suggested fixes
      Rails.logger.info "🔧 Suggested fixes for #{testable.class.name}:"
      feedback['fixes']&.each do |fix|
        Rails.logger.info "  - #{fix['test_name']}: #{fix['fix']}"
      end
      
      # In a more advanced implementation, this would:
      # 1. Parse the fix suggestions
      # 2. Apply them to the testable (update system prompt, parameters, etc.)
      # 3. Save the changes
      # For now, we just log and let the next attempt run
    end
  end
end

