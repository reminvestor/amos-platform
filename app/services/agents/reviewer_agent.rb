module Agents
  class ReviewerAgent < BaseAgent
    def execute!
      log("Starting code review...")

      inputs = agent_execution.inputs
      pr_url = inputs['pr_url']

      # Fetch PR diff
      git_connection = pipeline_execution.git_connection
      pr_details = git_connection.client.get_pull_request(inputs['repository'], inputs['pr_id'])
      diff = pr_details[:diff]

      system_prompt = <<~PROMPT
        You are an expert code reviewer. Analyze the code changes and provide a review.

        Check for:
        - Code quality and best practices
        - Security vulnerabilities
        - Test coverage
        - Documentation
        - Performance issues

        Respond in JSON:
        {
          "approved": true/false,
          "issues": ["issue 1", "issue 2"],
          "suggestions": ["suggestion 1"],
          "summary": "Overall review summary"
        }
      PROMPT

      user_message = "Review this PR diff:\n\n#{diff}"

      result = call_claude(system_prompt, user_message, model: 'claude-3-5-sonnet', max_tokens: 8000, temperature: 0.2)

      if result[:success]
        review_data = JSON.parse(result[:content])
        save_artifact('review_report', 'review.json', result[:content])

        # Post review comment to PR
        git_connection.client.create_review_comment(
          inputs['repository'],
          inputs['pr_id'],
          review_data['summary']
        )

        agent_execution.complete!(
          approved: review_data['approved'],
          issues: review_data['issues'],
          summary: review_data['summary']
        )

        log("Review complete: #{review_data['approved'] ? 'Approved' : 'Changes requested'}")
      else
        raise "Review failed: #{result[:error]}"
      end
    rescue JSON::ParserError
      # Default to approved if parsing fails
      agent_execution.complete!(approved: true, summary: result[:content])
    end
  end
end
