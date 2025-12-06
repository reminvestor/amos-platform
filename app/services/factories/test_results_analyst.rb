# frozen_string_literal: true

module Factories
  # AI-powered analyst that evaluates test results and provides context
  # Helps users understand if failures are critical or if tests are too strict
  class TestResultsAnalyst
    def initialize
      @bedrock_service = BedrockService.new
    end

    # Analyze a completed test session and provide recommendations
    def analyze(session)
      Rails.logger.info "🔍 Analyzing test results for #{session.testable_type} (Session ##{session.id})"
      
      testable = session.testable
      runs = session.factory_test_runs.includes(:factory_test_criteria)
      
      prompt = build_analysis_prompt(testable, session, runs)
      response = call_ai(prompt)
      analysis = parse_analysis(response)
      
      # Store analysis in session metadata
      session.update!(
        metadata: session.metadata.merge(
          'ai_analysis' => analysis,
          'analyzed_at' => Time.current.iso8601
        )
      )
      
      analysis
    rescue => e
      Rails.logger.error "Test analysis failed: #{e.message}"
      default_analysis(session)
    end

    # Quick analysis for a single test run
    def analyze_single_failure(run)
      criteria = run.factory_test_criteria
      
      prompt = <<~PROMPT
        A test failed. Evaluate if this is a critical issue or if the test might be too strict.

        **Test:** #{criteria.name}
        **Type:** #{criteria.test_type}
        **Required:** #{criteria.is_required ? 'Yes' : 'No'}
        **Expected:** #{criteria.expected_output || criteria.expected_values.to_json}
        **Actual:** #{run.actual_output.to_s.truncate(500)}
        **Error:** #{run.error_message}

        Return JSON:
        ```json
        {
          "severity": "critical|moderate|minor|negligible",
          "is_test_too_strict": true/false,
          "explanation": "Why this matters or doesn't",
          "suggestion": "What to do about it"
        }
        ```
      PROMPT

      response = call_ai(prompt)
      parse_single_analysis(response)
    rescue => e
      { severity: 'unknown', explanation: "Analysis failed: #{e.message}" }
    end

    private

    def build_analysis_prompt(testable, session, runs)
      # Build test results summary
      test_summaries = runs.map do |run|
        criteria = run.factory_test_criteria
        status = run.passed ? '✅ PASS' : '❌ FAIL'
        
        summary = "#{status} | #{criteria.name} (#{criteria.test_type}, #{criteria.is_required ? 'required' : 'optional'})"
        summary += "\n     Expected: #{criteria.expected_output.to_s.truncate(100)}" if criteria.expected_output.present?
        summary += "\n     Actual: #{run.actual_output.to_s.truncate(100)}" if run.actual_output.present?
        summary += "\n     Error: #{run.error_message}" if run.error_message.present?
        summary
      end.join("\n\n")

      <<~PROMPT
        You are a senior QA analyst reviewing test results for an AI-created #{testable.class.name.underscore.humanize}.

        ## Item Being Tested
        **Name:** #{testable.try(:name) || testable.id}
        **Description:** #{testable.try(:description).to_s.truncate(300)}

        ## Test Session Summary
        - **Attempt:** #{session.attempt_number} of #{session.max_attempts}
        - **Score:** #{(session.overall_score.to_f * 100).round}%
        - **Results:** #{session.passed_tests}/#{session.total_tests} passed

        ## Individual Test Results
        #{test_summaries}

        ## Your Analysis Task

        Provide a thoughtful analysis that helps the user understand:
        1. **Overall Quality:** Is this #{testable.class.name.underscore.humanize} ready for use?
        2. **Critical Issues:** Are there any failures that MUST be fixed?
        3. **Test Quality:** Are any tests overly strict or potentially flawed?
        4. **Recommendation:** Should the user accept this, request fixes, or reject it?

        Be practical and user-focused. Sometimes 70% is good enough. Sometimes a failing test is actually testing the wrong thing.

        Return a JSON object:
        ```json
        {
          "overall_quality": "excellent|good|acceptable|needs_work|poor",
          "quality_score": 0.85,
          "summary": "2-3 sentence summary for the user",
          "critical_issues": [
            {"test": "Test name", "why_critical": "Explanation"}
          ],
          "minor_issues": [
            {"test": "Test name", "impact": "Low/Medium", "suggestion": "Optional fix"}
          ],
          "potentially_strict_tests": [
            {"test": "Test name", "why_might_be_strict": "Explanation", "should_relax": true/false}
          ],
          "recommendation": {
            "action": "accept|fix_and_retry|reject",
            "confidence": 0.9,
            "reasoning": "Why this recommendation"
          },
          "user_message": "Friendly message to show the user explaining the results"
        }
        ```

        Return ONLY the JSON object.
      PROMPT
    end

    def call_ai(prompt)
      @bedrock_service.send_message(
        nil,
        [{ role: "user", content: prompt }],
        model: "claude-sonnet-4-5",
        temperature: 0.3,
        json_mode: true
      )
    end

    def parse_analysis(response)
      cleaned = response.to_s.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip
      analysis = JSON.parse(cleaned)
      
      # Ensure required fields
      {
        'overall_quality' => analysis['overall_quality'] || 'unknown',
        'quality_score' => analysis['quality_score']&.to_f || 0.0,
        'summary' => analysis['summary'] || 'Analysis complete.',
        'critical_issues' => analysis['critical_issues'] || [],
        'minor_issues' => analysis['minor_issues'] || [],
        'potentially_strict_tests' => analysis['potentially_strict_tests'] || [],
        'recommendation' => analysis['recommendation'] || { 'action' => 'review', 'reasoning' => 'Manual review recommended' },
        'user_message' => analysis['user_message'] || 'Test results have been analyzed.'
      }
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse analysis: #{e.message}"
      default_analysis(nil)
    end

    def parse_single_analysis(response)
      cleaned = response.to_s.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip
      JSON.parse(cleaned)
    rescue
      { severity: 'unknown', explanation: 'Could not analyze' }
    end

    def default_analysis(session)
      score = session&.overall_score.to_f
      quality = if score >= 0.9
                  'excellent'
                elsif score >= 0.7
                  'good'
                elsif score >= 0.5
                  'acceptable'
                else
                  'needs_work'
                end

      {
        'overall_quality' => quality,
        'quality_score' => score,
        'summary' => "#{(score * 100).round}% of tests passed. Manual review recommended.",
        'critical_issues' => [],
        'minor_issues' => [],
        'potentially_strict_tests' => [],
        'recommendation' => {
          'action' => score >= 0.7 ? 'accept' : 'review',
          'confidence' => 0.5,
          'reasoning' => 'Automated analysis unavailable - please review manually'
        },
        'user_message' => "Test results are available. #{score >= 0.7 ? 'Most tests passed!' : 'Some tests need attention.'}"
      }
    end
  end
end

