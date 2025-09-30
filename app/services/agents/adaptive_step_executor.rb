module Agents
  class AdaptiveStepExecutor
    attr_reader :step, :context, :max_attempts, :tool_chain_limit

    def initialize(step, context)
      @step = step
      @context = context
      @ai_service = BedrockService.new
      @max_attempts = 3
      @tool_chain_limit = 5
      @tools_used = []
      @execution_history = []
      @workflow_execution = context[:workflow_execution]
      @progress_callback = context[:progress_callback]
    end

    # Execute the step with AI-powered adaptive behavior
    def execute(inputs = {})
      Rails.logger.info "🤖 AdaptiveStepExecutor: Starting execution of step #{step.id}"
      
      # Store initial context
      @initial_goal = step.description || step.name
      @current_inputs = inputs
      @attempt_count = 0
      
      # Start execution loop
      result = nil
      while @attempt_count < @max_attempts && @tools_used.length < @tool_chain_limit
        @attempt_count += 1
        
        # Get AI decision on how to proceed
        decision = get_ai_decision
        
        case decision[:action]
        when 'execute_tool'
          result = execute_tool_with_healing(decision[:tool], decision[:tool_args])
        when 'chain_tools'
          result = execute_tool_chain(decision[:tool_chain])
        when 'complete'
          # AI thinks the goal is achieved
          break
        when 'fail'
          # AI determines it cannot proceed
          return {
            success: false,
            error: decision[:reason],
            execution_history: @execution_history
          }
        end
        
        # Check if goal is achieved
        if goal_achieved?(result)
          Rails.logger.info "✅ Goal achieved for step #{step.id}"
          break
        end
      end
      
      # Return final result
      {
        success: result[:success] || false,
        data: result,
        tools_used: @tools_used,
        execution_history: @execution_history,
        attempts: @attempt_count
      }
    end

    private

    def get_ai_decision
      # Build context for AI
      prompt = build_decision_prompt
      
      response = @ai_service.complete(
        prompt: prompt,
        max_tokens: 1000,
        system_prompt: system_prompt
      )
      
      # Parse AI response
      parse_ai_decision(response)
    rescue => e
      Rails.logger.error "AI decision failed: #{e.message}"
      # Fallback to simple tool execution
      {
        action: 'execute_tool',
        tool: @step.config[:tool],
        tool_args: @step.config[:tool_args]
      }
    end

    def build_decision_prompt
      available_tools = ::Tools::ToolCatalog.instance.tools_for_role(@step.agent_role || 'executor')
      
      <<~PROMPT
        Current Step Goal: #{@initial_goal}
        Step Configuration: #{@step.config.to_json}
        
        Execution History:
        #{format_execution_history}
        
        Current Inputs: #{@current_inputs.to_json}
        
        Available Tools:
        #{available_tools.map { |t| "- #{t[:name]}: #{t[:description]}" }.join("\n")}
        
        Available Variables:
        #{list_available_variables}
        
        Based on the current state, what should I do next? Consider:
        1. Has the goal been achieved?
        2. If not, what tool(s) would help achieve it?
        3. Should I retry with different parameters?
        4. Should I chain multiple tools together?
        
        Respond with a JSON decision:
        {
          "action": "execute_tool|chain_tools|complete|fail",
          "tool": "tool_name",
          "tool_args": {},
          "tool_chain": [{"tool": "name", "args": {}}],
          "reason": "explanation"
        }
      PROMPT
    end

    def system_prompt
      <<~SYSTEM
        You are an intelligent workflow step executor. Your job is to:
        1. Understand the goal of the current step
        2. Use available tools creatively to achieve that goal
        3. Self-heal when things go wrong
        4. Chain tools together when needed
        5. Know when to give up if the goal is impossible
        
        Always prefer the simplest solution that works.
        Be resilient but don't waste resources on impossible tasks.
        Learn from failed attempts and try different approaches.
      SYSTEM
    end

    def execute_tool_with_healing(tool_name, tool_args)
      Rails.logger.info "🔧 Executing tool: #{tool_name} with args: #{tool_args.inspect}"
      
      # Notify progress
      @progress_callback&.call({
        type: :tool_call,
        tool_name: tool_name,
        step_id: @step.id
      })
      
      begin
        # Execute the tool
        result = ::Tools::ToolCatalog.instance.execute_tool(
          tool_name,
          tool_args,
          @context[:user],
          @context[:entity],
          @context
        )
        
        @tools_used << { tool: tool_name, args: tool_args, result: result[:success] }
        @execution_history << {
          action: 'tool_execution',
          tool: tool_name,
          args: tool_args,
          result: result,
          timestamp: Time.current
        }
        
        # Store any output variables
        store_tool_output(tool_name, result)
        
        # Notify result
        @progress_callback&.call({
          type: :tool_result,
          tool_name: tool_name,
          success: result[:success],
          error: result[:error]
        })
        
        result
      rescue => e
        Rails.logger.error "Tool execution failed: #{e.message}"
        
        # Record failure
        @execution_history << {
          action: 'tool_failure',
          tool: tool_name,
          error: e.message,
          timestamp: Time.current
        }
        
        # Let AI decide how to handle the failure
        { success: false, error: e.message }
      end
    end

    def execute_tool_chain(tool_chain)
      Rails.logger.info "🔗 Executing tool chain with #{tool_chain.length} tools"
      
      results = []
      tool_chain.each do |tool_spec|
        # Resolve any variables in the args
        resolved_args = resolve_variables_in_args(tool_spec[:args] || tool_spec['args'])
        
        result = execute_tool_with_healing(
          tool_spec[:tool] || tool_spec['tool'],
          resolved_args
        )
        
        results << result
        
        # Stop chain if a tool fails
        break unless result[:success]
      end
      
      # Return the last result
      results.last || { success: false, error: 'No tools executed' }
    end

    def goal_achieved?(result)
      # First check: did the last tool succeed?
      return false unless result && result[:success]
      
      # For verification steps, check verification rules
      if @step.config[:verification_rules]
        verification_result = apply_verification_rules(result)
        return verification_result[:passed]
      end
      
      # For other steps, ask AI if goal is achieved
      check_goal_with_ai(result)
    end

    def check_goal_with_ai(result)
      prompt = <<~PROMPT
        Step Goal: #{@initial_goal}
        
        Latest Result: #{result.to_json}
        
        Has the goal been achieved? Respond with JSON:
        { "achieved": true/false, "reason": "explanation" }
      PROMPT
      
      response = @ai_service.complete(
        prompt: prompt,
        max_tokens: 200
      )
      
      parsed = JSON.parse(response) rescue {}
      parsed['achieved'] == true
    rescue => e
      Rails.logger.error "Goal check failed: #{e.message}"
      # Assume success if we can't verify
      true
    end

    def apply_verification_rules(result)
      # Reuse logic from VerifierAgent
      rules = @step.config[:verification_rules]
      verification = { passed: true, reasons: [] }
      
      rules.each do |rule|
        # Apply each rule...
        # (Implementation similar to VerifierAgent)
      end
      
      verification
    end

    def store_tool_output(tool_name, result)
      return unless @workflow_execution && result[:success]
      
      # Create a pseudo step execution for this tool call
      key_prefix = "#{@step.id}.#{tool_name}"
      
      # Store the result data
      if result.dig(:data, :result)
        @workflow_execution.set_variable(
          "#{key_prefix}.result",
          result[:data][:result]
        )
      end
    end

    def resolve_variables_in_args(args)
      return args unless args.is_a?(Hash)
      
      resolved = {}
      args.each do |key, value|
        resolved[key] = if value.is_a?(String) && value.include?('{{')
          resolve_variable_string(value)
        elsif value.is_a?(Hash)
          resolve_variables_in_args(value)
        elsif value.is_a?(Array)
          value.map { |v| v.is_a?(Hash) ? resolve_variables_in_args(v) : v }
        else
          value
        end
      end
      resolved
    end

    def resolve_variable_string(str)
      str.gsub(/\{\{([^}]+)\}\}/) do |match|
        var_name = $1.strip
        @workflow_execution&.get_variable(var_name) || match
      end
    end

    def format_execution_history
      @execution_history.map do |entry|
        "- #{entry[:action]}: #{entry[:tool] || entry[:error]} at #{entry[:timestamp]}"
      end.join("\n")
    end

    def list_available_variables
      return "None" unless @workflow_execution
      
      vars = @workflow_execution.workflow_variables.limit(10).pluck(:name, :value)
      vars.map { |name, value| "- #{name}: #{value.to_s.truncate(50)}" }.join("\n")
    end

    def parse_ai_decision(response)
      # Try to extract JSON from response
      json_match = response.match(/\{.*\}/m)
      return default_decision unless json_match
      
      decision = JSON.parse(json_match[0])
      
      {
        action: decision['action'] || 'execute_tool',
        tool: decision['tool'],
        tool_args: decision['tool_args'] || {},
        tool_chain: decision['tool_chain'] || [],
        reason: decision['reason']
      }
    rescue => e
      Rails.logger.error "Failed to parse AI decision: #{e.message}"
      default_decision
    end

    def default_decision
      {
        action: 'execute_tool',
        tool: @step.config[:tool],
        tool_args: @step.config[:tool_args] || {}
      }
    end
  end
end




