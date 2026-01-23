module AiAgents::Pipeline
  class ReviewerAgent < BaseAgent
    # Security patterns to detect in code
    SECURITY_PATTERNS = {
      secrets: [
        /(?:password|passwd|pwd)\s*[:=]\s*['"]\w+['"]/i,
        /(?:api[_-]?key|apikey)\s*[:=]\s*['"]\w+['"]/i,
        /(?:secret|token)\s*[:=]\s*['"]\w+['"]/i,
        /(?:aws[_-]?access[_-]?key|aws[_-]?secret)\s*[:=]/i,
        /(?:private[_-]?key|ssh[_-]?key)\s*[:=]/i
      ],
      vulnerabilities: [
        /eval\s*\(/i,                           # Code injection
        /system\s*\(/i,                         # Command injection risk
        /`[^`]*\$\{/,                          # Shell injection
        /exec\s*\(/i,                          # Command execution
        /innerHTML\s*=/i,                      # XSS risk
        /dangerouslySetInnerHTML/i,            # React XSS risk
        /sql\s*=\s*['"]\s*SELECT.*\$\{/i,    # SQL injection
        /\.raw\s*\(/i,                         # Raw SQL
        /File\.open.*"w"/i,                    # Unsafe file write
        /send_file.*params/i                   # Path traversal risk
      ],
      best_practices: [
        /TODO|FIXME|HACK/i,                    # Code quality markers
        /binding\.pry|debugger|console\.log/i, # Debug statements
        /rescue\s*=>\s*[^e]/i,                 # Silent exception handling
        /rescue\s+Exception/i                  # Overly broad rescue
      ]
    }

    def execute!
      log("Starting comprehensive code review...")
      log("Using Claude 3.5 Sonnet for analysis")

      inputs = agent_execution.inputs
      pr_url = inputs['pr_url']
      pr_number = inputs['pr_number'] || inputs['pr_id']
      repository = inputs['repository']

      unless pr_url && pr_number && repository
        raise "Missing required inputs: pr_url, pr_number, and repository"
      end

      log("Reviewing PR: #{pr_url}")

      # Get GitHub connection
      git_connection = pipeline_execution.git_connection
      raise "No GitHub connection configured" unless git_connection

      github_client = Git::GithubClient.new(git_connection)

      # Fetch PR diff
      log("Fetching PR diff from GitHub...")
      diff_result = github_client.get_pr_diff(repository, pr_number)

      unless diff_result[:success]
        raise "Failed to fetch PR diff: #{diff_result[:error]}"
      end

      diff = diff_result[:diff]
      log("Fetched diff (#{diff.bytesize} bytes)")

      # Fetch PR files
      log("Fetching changed files...")
      files_result = github_client.get_pr_files(repository, pr_number)
      files_changed = files_result[:success] ? files_result[:files] : []
      log("Found #{files_changed.length} changed files")

      # Run security scans
      log("Running security scans...")
      security_issues = scan_for_security_issues(diff, files_changed)

      # Run Claude review
      log("Running Claude code review...")
      review_result = run_claude_review(diff, inputs, security_issues)

      unless review_result[:success]
        raise "Claude review failed: #{review_result[:error]}"
      end

      review_data = review_result[:data]

      # Combine security issues with Claude's findings
      all_issues = (security_issues[:critical] + security_issues[:high] + security_issues[:medium]).uniq
      review_data['security_issues'] = security_issues
      review_data['total_issues_found'] = all_issues.length

      # Determine approval status
      has_critical_issues = security_issues[:critical].any?
      has_blocking_issues = security_issues[:high].any? || all_issues.length > 10

      approved = !has_critical_issues && !has_blocking_issues && review_data['approved']

      # Create review report artifact
      log("Creating review report...")
      review_report = build_review_report(review_data, security_issues, files_changed)
      save_artifact('review_report', 'review_report.md', review_report)

      # Create gate decision artifact
      log("Creating gate decision...")
      gate_decision = build_gate_decision(approved, review_data, security_issues)
      save_artifact('gate', 'gate.json', gate_decision.to_json)

      # Post review summary to PR
      log("Posting review to PR...")
      post_review_to_pr(github_client, repository, pr_number, review_data, security_issues, approved)

      # Complete agent execution
      decision = approved ? 'approve' : 'needs_changes'
      agent_execution.complete!(
        decision: decision,
        approved: approved,
        issues_count: all_issues.length,
        critical_issues: security_issues[:critical].length,
        high_issues: security_issues[:high].length,
        medium_issues: security_issues[:medium].length,
        test_coverage_adequate: review_data['test_coverage_adequate'],
        summary: review_data['summary']
      )

      log("Review complete: #{decision.upcase}")
      log("Critical: #{security_issues[:critical].length}, High: #{security_issues[:high].length}, Medium: #{security_issues[:medium].length}")
    end

    private

    # Scan for security issues in the diff
    def scan_for_security_issues(diff, files_changed)
      issues = {
        critical: [],
        high: [],
        medium: [],
        info: []
      }

      # Check for secrets
      SECURITY_PATTERNS[:secrets].each do |pattern|
        diff.scan(pattern) do |match|
          issues[:critical] << "⚠️ CRITICAL: Potential hardcoded secret detected: #{match[0..50]}..."
        end
      end

      # Check for vulnerabilities
      SECURITY_PATTERNS[:vulnerabilities].each do |pattern|
        diff.scan(pattern) do |match|
          issues[:high] << "⚠️ HIGH: Security vulnerability pattern detected: #{match[0..50]}..."
        end
      end

      # Check for best practice violations
      SECURITY_PATTERNS[:best_practices].each do |pattern|
        diff.scan(pattern) do |match|
          issues[:medium] << "ℹ️ MEDIUM: Code quality issue: #{match[0..50]}..."
        end
      end

      # Check test coverage
      has_tests = files_changed.any? { |f| f[:filename].include?('test') || f[:filename].include?('spec') }
      has_code = files_changed.any? { |f|
        f[:filename].match?(/\.(rb|js|ts|py|java|go)$/) &&
        !f[:filename].include?('test') &&
        !f[:filename].include?('spec')
      }

      if has_code && !has_tests
        issues[:high] << "⚠️ HIGH: Code changes without corresponding tests"
      end

      # Check for large files
      files_changed.each do |file|
        if file[:additions] && file[:additions] > 500
          issues[:medium] << "ℹ️ MEDIUM: Large file added (#{file[:additions]} lines): #{file[:filename]}"
        end
      end

      issues
    end

    # Run Claude review
    def run_claude_review(diff, inputs, security_issues)
      system_prompt = build_review_system_prompt(security_issues)
      user_message = build_review_user_message(diff, inputs)

      result = call_claude(
        system_prompt,
        user_message,
        model: 'qwen3-next-80b',
        max_tokens: 8000,
        temperature: 0.2
      )

      return { success: false, error: result[:error] } unless result[:success]

      # Parse JSON response
      begin
        review_data = JSON.parse(result[:content])
        { success: true, data: review_data }
      rescue JSON::ParserError => e
        log("Failed to parse Claude response as JSON, using raw content")
        {
          success: true,
          data: {
            'approved' => false,
            'summary' => result[:content],
            'issues' => [],
            'suggestions' => [],
            'test_coverage_adequate' => false
          }
        }
      end
    end

    def build_review_system_prompt(security_issues)
      critical_count = security_issues[:critical].length
      high_count = security_issues[:high].length

      <<~PROMPT
        You are an expert code reviewer for an AI development pipeline. Your role is to provide thorough,
        constructive code review focusing on quality, security, maintainability, and best practices.

        SECURITY SCAN RESULTS:
        - Critical Issues: #{critical_count}
        - High Priority Issues: #{high_count}

        #{critical_count > 0 ? "⚠️ CRITICAL SECURITY ISSUES DETECTED - Review carefully!" : ""}

        Review the code changes and provide analysis in the following areas:

        1. **Code Quality**
           - Clear, readable code
           - Proper error handling
           - Input validation
           - Following language/framework conventions

        2. **Security**
           - No hardcoded secrets or credentials
           - Proper authentication/authorization
           - Input sanitization
           - SQL injection prevention
           - XSS prevention

        3. **Testing**
           - Adequate test coverage
           - Tests for edge cases
           - Tests for error conditions

        4. **Documentation**
           - Clear comments for complex logic
           - Updated README/docs if needed
           - API documentation

        5. **Performance**
           - Efficient algorithms
           - Database query optimization
           - Caching where appropriate

        6. **Best Practices**
           - DRY (Don't Repeat Yourself)
           - SOLID principles
           - Proper separation of concerns

        Respond in JSON format:
        {
          "approved": true/false,
          "summary": "Overall review summary (2-3 sentences)",
          "issues": ["issue 1", "issue 2", ...],
          "suggestions": ["suggestion 1", "suggestion 2", ...],
          "strengths": ["strength 1", "strength 2", ...],
          "test_coverage_adequate": true/false,
          "documentation_adequate": true/false,
          "performance_concerns": ["concern 1", ...],
          "security_concerns": ["concern 1", ...]
        }

        IMPORTANT: Set "approved" to false if:
        - Critical security issues are present
        - No tests for new code
        - Major quality issues
        - Breaking changes without documentation
      PROMPT
    end

    def build_review_user_message(diff, inputs)
      ticket_context = ""
      if inputs['ticket_title']
        ticket_context = <<~CONTEXT
          Ticket: #{inputs['ticket_id']} - #{inputs['ticket_title']}

          Description:
          #{inputs['ticket_description']}

        CONTEXT
      end

      <<~MESSAGE
        #{ticket_context}

        Please review the following code changes:

        ```diff
        #{diff}
        ```

        Provide a thorough code review in JSON format.
      MESSAGE
    end

    def build_review_report(review_data, security_issues, files_changed)
      report = <<~REPORT
        # Code Review Report

        **Generated**: #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')}
        **Agent**: ReviewerAgent (Claude 3.5 Sonnet)
        **Decision**: #{review_data['approved'] ? '✅ APPROVED' : '❌ NEEDS CHANGES'}

        ---

        ## Summary

        #{review_data['summary']}

        ---

        ## Files Changed (#{files_changed.length})

        #{files_changed.map { |f| "- `#{f[:filename]}` (+#{f[:additions]} -#{f[:deletions]})" }.join("\n")}

        ---

        ## Security Scan Results

        ### Critical Issues (#{security_issues[:critical].length})
        #{security_issues[:critical].any? ? security_issues[:critical].map { |i| "- #{i}" }.join("\n") : "_None found_"}

        ### High Priority (#{security_issues[:high].length})
        #{security_issues[:high].any? ? security_issues[:high].map { |i| "- #{i}" }.join("\n") : "_None found_"}

        ### Medium Priority (#{security_issues[:medium].length})
        #{security_issues[:medium].any? ? security_issues[:medium].map { |i| "- #{i}" }.join("\n") : "_None found_"}

        ---

        ## Code Quality Review

        ### Issues Found
        #{review_data['issues']&.any? ? review_data['issues'].map { |i| "- #{i}" }.join("\n") : "_None identified_"}

        ### Suggestions
        #{review_data['suggestions']&.any? ? review_data['suggestions'].map { |s| "- #{s}" }.join("\n") : "_None provided_"}

        ### Strengths
        #{review_data['strengths']&.any? ? review_data['strengths'].map { |s| "- #{s}" }.join("\n") : "_Not specified_"}

        ---

        ## Coverage Analysis

        - **Test Coverage**: #{review_data['test_coverage_adequate'] ? '✅ Adequate' : '❌ Insufficient'}
        - **Documentation**: #{review_data['documentation_adequate'] ? '✅ Adequate' : '⚠️ Needs improvement'}

        ---

        ## Additional Concerns

        ### Performance
        #{review_data['performance_concerns']&.any? ? review_data['performance_concerns'].map { |c| "- #{c}" }.join("\n") : "_No concerns_"}

        ### Security
        #{review_data['security_concerns']&.any? ? review_data['security_concerns'].map { |c| "- #{c}" }.join("\n") : "_No additional concerns_"}

        ---

        ## Recommendation

        #{review_data['approved'] ?
          "✅ **APPROVED** - Code meets quality standards and is ready to proceed." :
          "❌ **CHANGES NEEDED** - Please address the issues above before proceeding."}

      REPORT

      report
    end

    def build_gate_decision(approved, review_data, security_issues)
      {
        decision: approved ? 'approve' : 'needs_changes',
        approved: approved,
        timestamp: Time.current.iso8601,
        agent: 'ReviewerAgent',
        model: 'qwen3-next-80b',
        metrics: {
          critical_issues: security_issues[:critical].length,
          high_issues: security_issues[:high].length,
          medium_issues: security_issues[:medium].length,
          total_issues: (security_issues[:critical] + security_issues[:high] + security_issues[:medium]).length,
          test_coverage_adequate: review_data['test_coverage_adequate'],
          documentation_adequate: review_data['documentation_adequate']
        },
        reasons: approved ?
          ["All quality checks passed", "No critical security issues", "Test coverage adequate"] :
          build_rejection_reasons(security_issues, review_data),
        next_step: approved ? 'proceed_to_testing' : 'return_to_implementation'
      }
    end

    def build_rejection_reasons(security_issues, review_data)
      reasons = []

      if security_issues[:critical].any?
        reasons << "Critical security issues detected (#{security_issues[:critical].length})"
      end

      if security_issues[:high].any?
        reasons << "High priority issues found (#{security_issues[:high].length})"
      end

      unless review_data['test_coverage_adequate']
        reasons << "Insufficient test coverage"
      end

      if review_data['issues']&.length.to_i > 5
        reasons << "Too many code quality issues (#{review_data['issues'].length})"
      end

      reasons << "Code quality standards not met" if reasons.empty?

      reasons
    end

    def post_review_to_pr(github_client, repository, pr_number, review_data, security_issues, approved)
      status_emoji = approved ? "✅" : "❌"
      decision = approved ? "APPROVED" : "CHANGES REQUESTED"

      comment_body = <<~COMMENT
        ## #{status_emoji} AI Code Review - #{decision}

        **Reviewer**: ReviewerAgent (Claude 3.5 Sonnet)
        **Timestamp**: #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')}

        ### Summary
        #{review_data['summary']}

        ### Security Scan
        - 🔴 Critical: #{security_issues[:critical].length}
        - 🟠 High: #{security_issues[:high].length}
        - 🟡 Medium: #{security_issues[:medium].length}

        #{security_issues[:critical].any? ? "#### ⚠️ Critical Security Issues\n#{security_issues[:critical].map { |i| "- #{i}" }.join("\n")}\n\n" : ""}

        ### Quality Metrics
        - Test Coverage: #{review_data['test_coverage_adequate'] ? '✅ Adequate' : '❌ Insufficient'}
        - Documentation: #{review_data['documentation_adequate'] ? '✅ Adequate' : '⚠️ Needs improvement'}

        #{review_data['issues']&.any? ? "### Issues\n#{review_data['issues'].first(5).map { |i| "- #{i}" }.join("\n")}\n#{review_data['issues'].length > 5 ? "\n_... and #{review_data['issues'].length - 5} more (see full report)_\n" : ""}\n" : ""}

        #{review_data['suggestions']&.any? ? "### Suggestions\n#{review_data['suggestions'].first(3).map { |s| "- #{s}" }.join("\n")}\n\n" : ""}

        ---
        _Full review report available in pipeline artifacts_
      COMMENT

      result = github_client.add_comment(repository, pr_number, comment_body)

      if result[:success]
        log("Posted review comment to PR")
      else
        log("Warning: Failed to post comment to PR: #{result[:error]}")
      end
    end
  end
end
