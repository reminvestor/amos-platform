# frozen_string_literal: true

module Workflows
  module Executors
    # ═══════════════════════════════════════════════════════════════
    # AGENT EXECUTORS
    # These invoke AI agents within workflows
    # ═══════════════════════════════════════════════════════════════

    # AgentInvokeExecutor - Invokes an AI agent with a task
    class AgentInvokeExecutor < BaseExecutor
      def execute
        log_info "Invoking agent"

        agent_id = config[:agent_id]
        return failure("Agent ID is required") if agent_id.blank?

        agent = AgentPlugin.find_by(id: agent_id)
        return failure("Agent not found: #{agent_id}") unless agent
        return failure("Agent is not active") unless agent.active?

        # Build the prompt from template
        prompt = interpolate(config[:prompt_template] || '')
        return failure("Prompt is required") if prompt.blank?

        # Build context for the agent
        agent_context = {
          workflow_execution_id: execution.id,
          workflow_step: step['step_id'],
          inputs: inputs.to_h,
          entity_id: entity.id,
          user_id: user&.id
        }

        wait_for_completion = config[:wait_for_completion] != false
        timeout_minutes = config[:timeout_minutes] || 5

        begin
          if wait_for_completion
            # Synchronous execution - wait for agent response
            result = execute_agent_sync(agent, prompt, agent_context, timeout_minutes)
          else
            # Async execution - queue and continue
            result = execute_agent_async(agent, prompt, agent_context)
          end

          if result[:success]
            success(
              response: result[:response],
              artifacts: result[:artifacts] || [],
              execution_id: result[:execution_id],
              agent_name: agent.name
            )
          else
            failure(result[:error])
          end
        rescue => e
          log_error "Agent invocation failed: #{e.message}"
          failure("Agent invocation failed: #{e.message}")
        end
      end

      private

      def execute_agent_sync(agent, prompt, context, timeout_minutes)
        # Create the execution
        agent_execution = AgentPluginExecution.create!(
          agent_plugin: agent,
          entity: entity,
          user: user,
          status: 'running',
          input_context: context.merge(task: prompt)
        )

        # Execute with timeout
        Timeout.timeout(timeout_minutes * 60) do
          # Use the standard plugin executor
          executor = Agents::StandardPluginExecutor.new(
            agent_plugin: agent,
            user: user,
            entity: entity,
            context: context
          )

          result = executor.execute(prompt)

          agent_execution.update!(
            status: 'completed',
            output_data: result,
            completed_at: Time.current
          )

          {
            success: true,
            response: result[:response] || result[:output],
            artifacts: result[:artifacts],
            execution_id: agent_execution.id
          }
        end
      rescue Timeout::Error
        agent_execution&.update!(status: 'failed', error_message: 'Timeout')
        { success: false, error: "Agent execution timed out after #{timeout_minutes} minutes" }
      rescue => e
        agent_execution&.update!(status: 'failed', error_message: e.message)
        { success: false, error: e.message }
      end

      def execute_agent_async(agent, prompt, context)
        # Create the execution
        agent_execution = AgentPluginExecution.create!(
          agent_plugin: agent,
          entity: entity,
          user: user,
          status: 'running',
          input_context: context.merge(task: prompt)
        )

        # Queue for background execution
        AgentPluginExecutionJob.perform_later(
          agent_execution.id,
          prompt,
          context.merge(
            workflow_callback: {
              execution_id: execution.id,
              step_id: step['step_id']
            }
          )
        )

        {
          success: true,
          response: "Agent task queued",
          execution_id: agent_execution.id,
          async: true
        }
      end
    end

    # AgentDecideExecutor - Uses AI to make a decision
    class AgentDecideExecutor < BaseExecutor
      def execute
        log_info "Making AI decision"

        decision_prompt = interpolate(config[:decision_prompt] || '')
        return failure("Decision prompt is required") if decision_prompt.blank?

        # Build context for decision
        context_template = config[:context_template]
        decision_context = if context_template.present?
          interpolate(context_template)
        else
          inputs.to_h.merge(context.to_h).to_json
        end

        options = config[:options] || []

        begin
          result = make_decision(decision_prompt, decision_context, options)

          success(
            decision: result[:decision],
            reasoning: result[:reasoning],
            confidence: result[:confidence]
          )
        rescue => e
          log_error "AI decision failed: #{e.message}"
          failure("AI decision failed: #{e.message}")
        end
      end

      private

      def make_decision(prompt, context, options)
        system_prompt = build_decision_system_prompt(options)
        
        user_prompt = <<~PROMPT
          ## Decision Context
          #{context}

          ## Decision Required
          #{prompt}
        PROMPT

        # Use Bedrock for the decision
        bedrock = BedrockService.new
        response = bedrock.send_message(
          messages: [{ role: 'user', content: user_prompt }],
          system: system_prompt,
          max_tokens: 500,
          temperature: 0.3  # Lower temperature for more consistent decisions
        )

        parse_decision_response(response, options)
      end

      def build_decision_system_prompt(options)
        prompt = <<~PROMPT
          You are a decision-making assistant within an automated workflow.
          Your job is to analyze the context and make a clear decision.

          IMPORTANT: Your response must be valid JSON with this exact structure:
          {
            "decision": "your_decision_here",
            "reasoning": "brief explanation of why",
            "confidence": 0.85
          }

        PROMPT

        if options.any?
          prompt += <<~OPTIONS

            The decision MUST be one of these options:
            #{options.map { |o| "- #{o}" }.join("\n")}

            Choose the option that best fits the context.
          OPTIONS
        end

        prompt
      end

      def parse_decision_response(response, options)
        # Try to parse JSON from response
        json_match = response.match(/\{[^{}]*"decision"[^{}]*\}/m)
        
        if json_match
          parsed = JSON.parse(json_match[0])
          decision = parsed['decision']
          
          # Validate against options if provided
          if options.any? && !options.include?(decision)
            # Try to find closest match
            closest = options.find { |o| decision.to_s.downcase.include?(o.downcase) }
            decision = closest if closest
          end

          {
            decision: decision,
            reasoning: parsed['reasoning'] || 'No reasoning provided',
            confidence: (parsed['confidence'] || 0.7).to_f
          }
        else
          # Fallback - extract first line as decision
          lines = response.strip.split("\n")
          {
            decision: lines.first.to_s.strip,
            reasoning: lines[1..-1]&.join(' ') || 'Unable to parse reasoning',
            confidence: 0.5
          }
        end
      rescue JSON::ParserError
        {
          decision: response.strip.split("\n").first,
          reasoning: 'Failed to parse structured response',
          confidence: 0.3
        }
      end
    end
  end
end
