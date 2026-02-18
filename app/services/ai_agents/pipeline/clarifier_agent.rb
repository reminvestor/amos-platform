module AiAgents::Pipeline
  class ClarifierAgent < BaseAgent
    def execute!
      log("Starting clarification analysis for ticket: #{pipeline_execution.ticket_id}")

      # Get ticket data from inputs
      inputs = agent_execution.inputs
      ticket_title = inputs['ticket_title']
      ticket_description = inputs['ticket_description']
      ticket_metadata = inputs['ticket_metadata'] || {}

      log("Analyzing ticket: #{ticket_title}")

      # Build prompts
      system_prompt = build_system_prompt
      user_message = build_user_message(ticket_title, ticket_description, ticket_metadata)

      # Call Claude Haiku 4.5 (fast and cost-effective: ~$0.02 per ticket)
      result = call_claude(
        system_prompt,
        user_message,
        model: 'claude-haiku-4-5',
        max_tokens: 4000,
        temperature: 0.7
      )

      if result[:success]
        analyze_response(result[:content])
      else
        log("ERROR: Clarification failed: #{result[:error]}")
        raise "Clarification failed: #{result[:error]}"
      end
    end

    private

    def build_system_prompt
      <<~PROMPT
        You are a requirements clarification agent for an AI development pipeline.

        Your job is to analyze software development tickets and determine if they contain
        enough information for implementation, or if they need clarification.

        Analyze the ticket for:
        - **Ambiguous requirements**: Vague or unclear descriptions
        - **Missing acceptance criteria**: No clear definition of "done"
        - **Unclear technical specifications**: Implementation details not specified
        - **Dependencies or integrations**: External systems or APIs not mentioned
        - **Edge cases**: Error handling, validation, boundary conditions not covered
        - **User experience**: UI/UX details missing
        - **Performance requirements**: Scaling, speed, or resource constraints not defined
        - **Security concerns**: Authentication, authorization, data protection not addressed

        Respond in JSON format:
        {
          "needs_clarification": true/false,
          "confidence": 0.0-1.0,
          "questions": [
            {
              "category": "technical|business|ux|security|performance",
              "question": "Specific question text",
              "importance": "critical|high|medium|low"
            }
          ],
          "summary": "Brief 1-2 sentence summary of what the ticket is asking for",
          "requirements": [
            "Clear requirement 1",
            "Clear requirement 2"
          ],
          "risks": [
            "Potential risk or concern"
          ]
        }

        **Rules**:
        - Generate 3-5 questions maximum if clarification is needed
        - Prioritize critical and high importance questions
        - If the ticket is clear and actionable, set needs_clarification to false
        - Confidence should reflect how clear the requirements are (0.0 = very unclear, 1.0 = crystal clear)
        - Extract explicit requirements even when asking questions
        - Identify potential risks or concerns

        **Examples of good questions**:
        - "Should the user authentication support OAuth providers (Google, GitHub) or just email/password?"
        - "What should happen if the API request fails - retry, show error, or fall back to cached data?"
        - "Are there any performance requirements for the search feature (e.g., max response time)?"

        **Examples of bad questions**:
        - "What framework should we use?" (Implementation detail)
        - "Do you want this feature?" (Ticket already requests it)
        - "Should we write tests?" (Always yes)
      PROMPT
    end

    def build_user_message(title, description, metadata)
      # Build comprehensive context
      context = <<~MESSAGE
        Please analyze this ticket:

        **Title**: #{title}

        **Description**:
        #{description || '(No description provided)'}
      MESSAGE

      # Add metadata if available
      if metadata.present?
        context += "\n**Additional Context**:\n"
        context += "- Priority: #{metadata['priority']}\n" if metadata['priority']
        context += "- Labels: #{metadata['labels'].join(', ')}\n" if metadata['labels']&.any?
        context += "- Components: #{metadata['components'].join(', ')}\n" if metadata['components']&.any?
        context += "- Story Points: #{metadata['story_points']}\n" if metadata['story_points']
        context += "- Assignee: #{metadata['assignee']}\n" if metadata['assignee']
      end

      context += <<~MESSAGE

        Determine if clarification is needed before implementation can begin.
        If yes, generate specific, actionable questions.
        If no, extract and summarize the clear requirements.

        Respond in JSON format only.
      MESSAGE

      context
    end

    def analyze_response(response_text)
      log("Parsing clarification response...")

      # Parse JSON response
      response_data = JSON.parse(response_text)
      needs_clarification = response_data['needs_clarification']
      questions = response_data['questions'] || []
      summary = response_data['summary']
      requirements = response_data['requirements'] || []
      confidence = response_data['confidence'] || 0.5
      risks = response_data['risks'] || []

      log("Needs clarification: #{needs_clarification}, Confidence: #{confidence}")
      log("Questions: #{questions.size}, Requirements: #{requirements.size}")

      # Save artifacts
      save_clarification_artifacts(response_data)

      # Create interaction if clarification is needed
      if needs_clarification && questions.any?
        create_clarification_interaction(questions, summary)
        log("Created clarification interaction with #{questions.size} questions")
      end

      # Set outputs for orchestrator
      outputs = {
        needs_clarification: needs_clarification,
        questions: questions,
        summary: summary,
        requirements: requirements,
        confidence: confidence,
        risks: risks,
        question_count: questions.size
      }

      agent_execution.complete!(outputs)

      log("Clarification analysis complete: #{needs_clarification ? "#{questions.size} questions generated" : 'Requirements clear, proceeding to planning'}")

    rescue JSON::ParserError => e
      log("ERROR: Failed to parse JSON response: #{e.message}")
      log("Raw response: #{response_text}")

      # Try to extract useful information from non-JSON response
      # Default to NOT needing clarification if we can't parse (fail open)
      agent_execution.complete!(
        needs_clarification: false,
        summary: response_text.truncate(500),
        requirements: [],
        confidence: 0.3,
        parse_error: true,
        error_message: e.message
      )
    end

    def save_clarification_artifacts(response_data)
      # Save full JSON response
      save_artifact('clarifications', 'clarification_analysis.json', JSON.pretty_generate(response_data))

      # Save human-readable markdown
      markdown = build_markdown_report(response_data)
      save_artifact('clarifications', 'clarifications.md', markdown)

      # Save requirements checklist if any
      if response_data['requirements']&.any?
        checklist = build_requirements_checklist(response_data['requirements'])
        save_artifact('clarifications', 'requirements_checklist.yaml', checklist)
      end
    end

    def build_markdown_report(data)
      report = <<~MARKDOWN
        # Clarification Analysis

        **Ticket**: #{pipeline_execution.ticket_id} - #{pipeline_execution.ticket_title}
        **Status**: #{data['needs_clarification'] ? '⚠️ Needs Clarification' : '✅ Clear to Proceed'}
        **Confidence**: #{(data['confidence'] * 100).round}%

        ## Summary

        #{data['summary']}

        ## Requirements Identified

      MARKDOWN

      if data['requirements']&.any?
        data['requirements'].each_with_index do |req, idx|
          report += "#{idx + 1}. #{req}\n"
        end
      else
        report += "*No explicit requirements identified*\n"
      end

      report += "\n## Risks & Concerns\n\n"
      if data['risks']&.any?
        data['risks'].each do |risk|
          report += "- ⚠️ #{risk}\n"
        end
      else
        report += "*No significant risks identified*\n"
      end

      if data['needs_clarification'] && data['questions']&.any?
        report += "\n## Questions for Clarification\n\n"
        data['questions'].each_with_index do |q, idx|
          importance_emoji = case q['importance']
                            when 'critical' then '🔴'
                            when 'high' then '🟠'
                            when 'medium' then '🟡'
                            else '🟢'
                            end
          report += "### #{idx + 1}. [#{q['category']&.upcase}] #{importance_emoji} #{q['importance']&.capitalize}\n\n"
          report += "#{q['question']}\n\n"
        end
      end

      report += "\n---\n*Generated by ClarifierAgent using Claude 3.5 Haiku*\n"
      report
    end

    def build_requirements_checklist(requirements)
      checklist = {
        'requirements' => requirements.map.with_index { |req, idx|
          {
            'id' => "REQ-#{idx + 1}",
            'description' => req,
            'status' => 'pending',
            'verified' => false
          }
        },
        'generated_at' => Time.current.iso8601,
        'ticket_id' => pipeline_execution.ticket_id
      }

      YAML.dump(checklist)
    end

    def create_clarification_interaction(questions, summary)
      # Format questions for human review
      question_text = "## Clarification Needed for #{pipeline_execution.ticket_id}\n\n"
      question_text += "**Summary**: #{summary}\n\n"
      question_text += "**Questions**:\n\n"

      questions.each_with_index do |q, idx|
        question_text += "#{idx + 1}. **[#{q['category']&.upcase}]** #{q['question']}\n"
        question_text += "   *Importance: #{q['importance']}*\n\n"
      end

      # Create interaction (will auto-notify via callback)
      interaction = pipeline_execution.pipeline_interactions.create!(
        interaction_type: 'clarification',
        channel: default_notification_channel,
        question: question_text,
        status: :pending,
        asked_at: Time.current
        # timeout_at will be set automatically (2 hours)
      )

      log("Created interaction ##{interaction.id} via #{interaction.channel}")
      interaction
    end

    def default_notification_channel
      # Get from environment or entity settings
      ENV['DEFAULT_NOTIFICATION_CHANNEL'] || 'slack'
    end
  end
end
