# frozen_string_literal: true

module Tools
  class DeepReasoningTool < BaseTool
    def self.read_only?
      true # Reasoning doesn't modify entity data
    end

    def self.metadata
      {
        name: "deep_reasoning",
        description: <<~DESC.strip,
          Use DeepSeek R1 for complex reasoning, analysis, and multi-step problem solving.
          This model shows its thinking process, making it excellent for:
          
          • Complex analysis requiring multiple logical steps
          • Mathematical or quantitative reasoning
          • Code review and debugging with explanations
          • Strategic planning and decision frameworks
          • Breaking down ambiguous problems
          • Evaluating pros/cons of different approaches
          
          The model will "think out loud" - you'll see its reasoning process.
          Use this when you need thorough analysis, not just a quick answer.
        DESC
        category: "reasoning",
        input_schema: {
          type: "object",
          properties: {
            question: {
              type: "string",
              description: "The complex question or problem to analyze. Be specific and provide context."
            },
            context: {
              type: "string",
              description: "Optional additional context, data, or constraints to consider."
            },
            max_thinking_tokens: {
              type: "integer",
              description: "Maximum tokens for reasoning (default: 4000). Higher = more thorough but slower."
            }
          },
          required: ["question"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      question = get_arg(args, :question)
      additional_context = get_arg(args, :context, "")
      max_tokens = get_arg(args, :max_thinking_tokens, 4000)

      # Validate required args
      if error = validate_required_args(args, [:question])
        return error
      end

      begin
        # Build the prompt for deep reasoning
        system_prompt = build_reasoning_prompt
        user_message = build_user_message(question, additional_context)

        Rails.logger.info "🧠 Deep Reasoning starting with DeepSeek R1"
        start_time = Time.current

        # Use BedrockService to call DeepSeek R1
        bedrock = BedrockService.new(user: user, entity: entity)
        
        # DeepSeek R1 via Converse API
        response = bedrock.send_message_converse(
          system_prompt,
          [{ role: "user", content: [{ text: user_message }] }],
          model: "deepseek-r1",
          max_tokens: max_tokens,
          temperature: 0.7,
          tools: []
        )

        duration_ms = ((Time.current - start_time) * 1000).round(2)

        if response[:success]
          content = response[:content] || response[:text]
          
          # Extract thinking and answer if R1 includes thinking tags
          thinking, answer = extract_thinking_and_answer(content)
          
          Rails.logger.info "🧠 Deep Reasoning completed in #{duration_ms}ms"
          
          success_response(
            question: question,
            thinking_process: thinking,
            answer: answer,
            full_response: content,
            model: "DeepSeek R1",
            duration_ms: duration_ms,
            tokens: response[:tokens],
            tip: "The thinking_process shows how the model reasoned through the problem."
          )
        else
          error_response(
            "Deep reasoning failed: #{response[:error]}",
            model: "deepseek-r1",
            duration_ms: duration_ms
          )
        end
      rescue => e
        Rails.logger.error "Deep reasoning error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        error_response("Deep reasoning failed: #{e.message}")
      end
    end

    private

    def build_reasoning_prompt
      <<~PROMPT
        You are a deep reasoning assistant. Your job is to think through complex problems step by step.
        
        APPROACH:
        1. Break down the problem into components
        2. Consider multiple angles and perspectives
        3. Reason through each step explicitly
        4. Identify assumptions and uncertainties
        5. Draw a clear, well-supported conclusion
        
        Show your thinking process. It's better to be thorough than fast.
        
        If the question involves data, calculations, or code - work through it step by step.
        If there are trade-offs, explicitly list pros and cons.
        If you're uncertain, explain what would help resolve the uncertainty.
      PROMPT
    end

    def build_user_message(question, context)
      parts = ["Question: #{question}"]
      
      if context.present?
        parts << "\nAdditional Context:\n#{context}"
      end
      
      parts.join("\n")
    end

    def extract_thinking_and_answer(content)
      # DeepSeek R1 often uses <think>...</think> tags for reasoning
      thinking_match = content.match(/<think>(.*?)<\/think>/m)
      
      if thinking_match
        thinking = thinking_match[1].strip
        answer = content.sub(/<think>.*?<\/think>/m, "").strip
        [thinking, answer]
      else
        # If no explicit tags, the whole response is the answer with embedded reasoning
        [nil, content]
      end
    end
  end
end

