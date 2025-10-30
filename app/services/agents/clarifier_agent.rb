module Agents
  class ClarifierAgent < BaseAgent
    def execute!
      log("Starting clarification analysis...")

      inputs = agent_execution.inputs
      ticket_title = inputs['ticket_title']
      ticket_description = inputs['ticket_description']

      system_prompt = build_system_prompt
      user_message = build_user_message(ticket_title, ticket_description)

      result = call_claude(
        system_prompt,
        user_message,
        model: 'claude-3-5-haiku',  # Fast and cost-effective
        temperature: 0.7
      )

      if result[:success]
        analyze_response(result[:content])
      else
        raise "Clarification failed: #{result[:error]}"
      end
    end

    private

    def build_system_prompt
      <<~PROMPT
        You are a requirements clarification agent for an AI development pipeline.

        Your job is to analyze ticket descriptions and determine if they are clear enough
        for implementation, or if they need clarification.

        Respond in JSON format:
        {
          "needs_clarification": true/false,
          "questions": ["question 1", "question 2", ...],
          "summary": "Brief summary of the ticket",
          "requirements": ["requirement 1", "requirement 2", ...]
        }

        Ask clarifying questions about:
        - Ambiguous requirements
        - Missing acceptance criteria
        - Unclear technical specifications
        - Dependencies or integrations not mentioned
        - Edge cases not covered

        If the ticket is clear and complete, set needs_clarification to false and
        provide a requirements summary.
      PROMPT
    end

    def build_user_message(title, description)
      <<~MESSAGE
        Please analyze this ticket:

        Title: #{title}

        Description:
        #{description}

        Determine if clarification is needed. If yes, generate specific questions.
        If no, extract and summarize the requirements.

        Respond in JSON format only.
      MESSAGE
    end

    def analyze_response(response_text)
      # Parse JSON response
      response_data = JSON.parse(response_text)

      # Save clarification artifact
      save_artifact('clarifications', 'clarifications.json', response_text)

      # Set outputs
      agent_execution.complete!(
        needs_clarification: response_data['needs_clarification'],
        questions: response_data['questions'],
        summary: response_data['summary'],
        requirements: response_data['requirements']
      )

      log("Clarification complete: #{response_data['needs_clarification'] ? 'Questions generated' : 'Requirements clear'}")
    rescue JSON::ParserError => e
      log("Failed to parse clarification response: #{e.message}")
      # Default to needing clarification if parsing fails
      agent_execution.complete!(
        needs_clarification: false,
        summary: response_text
      )
    end
  end
end
