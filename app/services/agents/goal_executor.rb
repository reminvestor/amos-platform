module Agents
  class GoalExecutor < PhaseExecutor
    
    def execute
      phase_id = @phase[:id] || @phase['id']
      goal = @phase[:goal] || @phase['goal']
      
      Rails.logger.info "🎯 GoalExecutor: Starting phase #{phase_id}"
      Rails.logger.info "🎯 Goal: #{goal}"
      
      notify_progress("Working on: #{goal}")
      
      # Get execution strategy
      strategy = @phase[:execution_strategy] || @phase['execution_strategy'] || {}
      approach = strategy[:approach] || strategy['approach'] || 'adaptive'
      
      # Get constraints
      constraints = strategy[:constraints] || strategy['constraints'] || {}
      
      # Get allowed tools
      allowed_tools = strategy[:allowed_tools] || strategy['allowed_tools'] || []
      
      # Get AI instructions
      ai_instructions = @phase[:ai_instructions] || @phase['ai_instructions']
      
      # Get required data from previous phases
      required_data = gather_required_data
      
      case approach.to_s
      when 'adaptive'
        execute_adaptively(goal, allowed_tools, constraints, ai_instructions, required_data)
      when 'prescribed'
        execute_prescribed(strategy)
      else
        execute_adaptively(goal, allowed_tools, constraints, ai_instructions, required_data)
      end
    end
    
    private
    
    def gather_required_data
      requires = @phase[:requires_from_previous] || @phase['requires_from_previous'] || []
      data = {}
      
      requires.each do |requirement|
        # Look for this data in workflow context
        context_data = get_workflow_context
        
        # Find matching keys
        matching_keys = context_data.keys.select { |key| key.to_s.include?(requirement.to_s) }
        matching_keys.each do |key|
          data[key] = context_data[key]
        end
      end
      
      Rails.logger.info "📋 Gathered required data: #{data.keys.join(', ')}"
      data
    end
    
    def execute_adaptively(goal, allowed_tools, constraints, ai_instructions, required_data)
      max_attempts = @phase.dig(:adaptive, :max_attempts) || 
                    @phase.dig('adaptive', 'max_attempts') || 3
      
      attempt = 0
      result = nil
      
      while attempt < max_attempts
        attempt += 1
        Rails.logger.info "🔄 Attempt #{attempt} of #{max_attempts}"
        
        # Get AI decision on how to proceed
        action_plan = get_ai_action_plan(goal, allowed_tools, required_data, ai_instructions, attempt)
        
        Rails.logger.info "📋 AI Action Plan: #{action_plan.inspect}"
        
        # Execute the plan
        result = execute_action_plan(action_plan, constraints)
        
        # Check success criteria
        if meets_success_criteria?(result)
          Rails.logger.info "✅ Goal achieved!"
          
          # Store result in workflow context
          store_phase_output(result[:data] || {}, 'phase_output')
          
          notify_progress("Goal achieved: #{goal}", type: 'phase_complete')
          
          return {
            success: true,
            status: 'completed',
            data: result[:data],
            phase: @phase[:id] || @phase['id'],
            attempts: attempt
          }
        else
          Rails.logger.warn "⚠️ Attempt #{attempt} did not meet success criteria"
          
          # If self-healing is enabled and this isn't the last attempt
          if should_attempt_fix?(attempt, max_attempts)
            notify_progress("Attempting to fix issues...", type: 'self_healing')
            result = attempt_self_healing(result, goal)
            
            if result[:success]
              store_phase_output(result[:data] || {}, 'phase_output')
              notify_progress("Goal achieved after self-healing!", type: 'phase_complete')
              
              return {
                success: true,
                status: 'completed',
                data: result[:data],
                phase: @phase[:id] || @phase['id'],
                attempts: attempt,
                self_healed: true
              }
            end
          end
        end
      end
      
      # Max attempts reached without success
      {
        success: false,
        status: 'failed',
        error: "Could not achieve goal after #{max_attempts} attempts",
        phase: @phase[:id] || @phase['id'],
        partial_result: result
      }
    end
    
    def get_ai_action_plan(goal, allowed_tools, required_data, ai_instructions, attempt)
      prompt = <<~PROMPT
        You need to achieve this goal: #{goal}
        
        Available Tools:
        #{allowed_tools.map { |t| "- #{t}" }.join("\n")}
        
        Available Data from Previous Phases:
        #{JSON.pretty_generate(required_data)}
        
        Available Context:
        #{JSON.pretty_generate(get_workflow_context)}
        
        Instructions:
        #{ai_instructions}
        
        This is attempt #{attempt}. #{attempt > 1 ? "Previous attempts did not fully succeed. Try a different approach." : ""}
        
        Create an action plan to achieve the goal. You can:
        1. Execute a single tool
        2. Chain multiple tools together
        3. Use data from context to inform tool arguments
        
        Respond with JSON:
        {
          "approach": "single_tool|tool_chain",
          "reasoning": "why this approach will work",
          "actions": [
            {
              "tool": "tool_name",
              "args": { "arg1": "value1" },
              "description": "what this tool does"
            }
          ]
        }
      PROMPT
      
      ai_decide(prompt, 
        expect_json: true,
        system_prompt: goal_execution_system_prompt,
        max_tokens: 2000
      )
    end
    
    def execute_action_plan(plan, constraints)
      return { success: false, error: "Invalid plan" } unless plan.is_a?(Hash)
      
      actions = plan['actions'] || []
      results = []
      
      # Check constraints
      if constraints['max_ai_calls'] && actions.length > constraints['max_ai_calls']
        return { 
          success: false, 
          error: "Plan exceeds max_ai_calls constraint (#{constraints['max_ai_calls']})" 
        }
      end
      
      # Execute each action
      actions.each_with_index do |action, index|
        tool_name = action['tool']
        tool_args = action['args'] || {}
        
        Rails.logger.info "🔧 Executing action #{index + 1}: #{tool_name}"
        notify_progress("#{action['description'] || "Using #{tool_name}"}...", type: 'tool_start', tool_name: tool_name)
        
        # Resolve any variable references in args
        resolved_args = resolve_tool_args(tool_args)
        
        # Execute the tool
        result = execute_tool(tool_name, resolved_args)
        
        notify_progress("Completed: #{tool_name}", type: 'tool_complete', tool_name: tool_name)
        
        results << {
          tool: tool_name,
          args: resolved_args,
          result: result,
          success: result[:success] || result['success']
        }
        
        # Stop if a tool fails (unless chaining is allowed)
        unless result[:success] || result['success']
          return {
            success: false,
            error: result[:error] || result['error'] || "Tool #{tool_name} failed",
            results: results
          }
        end
      end
      
      # Combine all results
      combined_data = results.reduce({}) do |acc, r|
        tool_result = r[:result]
        if tool_result.is_a?(Hash)
          acc.merge!(tool_result)
        end
        acc
      end
      
      {
        success: true,
        data: combined_data,
        results: results,
        actions_executed: actions.length
      }
    end
    
    def resolve_tool_args(args)
      return args unless args.is_a?(Hash)
      
      resolved = args.deep_dup
      context_data = get_workflow_context
      
      resolved.each do |key, value|
        if value.is_a?(String) && value.match?(/\{\{(.+?)\}\}/)
          # Replace {{variable}} with actual value
          value.scan(/\{\{(.+?)\}\}/).each do |match|
            var_name = match[0].strip
            
            # Look for variable in context
            resolved_value = context_data[var_name] || 
                           context_data[var_name.to_sym] ||
                           find_variable_in_context(var_name)
            
            if resolved_value
              resolved[key] = value.gsub("{{#{var_name}}}", resolved_value.to_s)
              Rails.logger.info "✅ Resolved {{#{var_name}}} to #{resolved_value}"
            else
              Rails.logger.warn "⚠️ Could not resolve {{#{var_name}}}"
            end
          end
        elsif value.is_a?(Hash)
          resolved[key] = resolve_tool_args(value)
        elsif value.is_a?(Array)
          resolved[key] = value.map { |v| v.is_a?(Hash) ? resolve_tool_args(v) : v }
        end
      end
      
      resolved
    end
    
    def find_variable_in_context(var_name)
      context_data = get_workflow_context
      
      # Try fuzzy matching
      matching_key = context_data.keys.find do |key|
        key.to_s.end_with?(var_name) || key.to_s.include?(var_name)
      end
      
      matching_key ? context_data[matching_key] : nil
    end
    
    def meets_success_criteria?(result)
      success_criteria = @phase.dig(:execution_strategy, :success_when) ||
                        @phase.dig('execution_strategy', 'success_when') || []
      
      return result[:success] if success_criteria.empty?
      
      # Check each criterion
      success_criteria.all? do |criterion, expected_value|
        case criterion.to_s
        when 'landing_page_id_exists'
          result.dig(:data, 'landing_page_id').present? || 
          result.dig(:data, :landing_page_id).present?
        when 'campaign_id_exists'
          result.dig(:data, 'campaign_id').present? || 
          result.dig(:data, :campaign_id).present?
        when 'html_content_generated', 'html_generated'
          result.dig(:data, 'html_content').present? || 
          result.dig(:data, :html_content).present?
        when 'all_required_sections_present'
          # Could validate HTML sections here
          true
        else
          # Generic check
          result[:success] && expected_value
        end
      end
    end
    
    def should_attempt_fix?(attempt, max_attempts)
      return false if attempt >= max_attempts
      
      self_healing_enabled = @phase.dig(:adaptive, :self_healing) ||
                            @phase.dig('adaptive', 'self_healing')
      
      self_healing_enabled != false
    end
    
    def attempt_self_healing(failed_result, goal)
      Rails.logger.info "🔧 Attempting self-healing..."
      
      # Use FixerAgent if available
      fixer = Agents::Specialized::FixerAgent.new(
        task_session: @context[:task_session],
        initial_context: @context
      )
      
      fix_context = {
        phase_id: @phase[:id] || @phase['id'],
        goal: goal,
        failed_result: failed_result,
        available_tools: @phase.dig(:execution_strategy, :allowed_tools) ||
                        @phase.dig('execution_strategy', 'allowed_tools')
      }
      
      fix_result = fixer.fix_failed_step(
        @phase,
        { error: failed_result[:error] },
        fix_context
      )
      
      if fix_result[:success]
        Rails.logger.info "✅ Self-healing successful!"
        {
          success: true,
          data: fix_result[:data] || {},
          self_healed: true
        }
      else
        Rails.logger.warn "⚠️ Self-healing failed"
        failed_result
      end
    end
    
    def execute_prescribed(strategy)
      # Fallback to prescribed execution if needed
      # This would be similar to old step-by-step execution
      
      {
        success: false,
        error: "Prescribed execution not yet implemented"
      }
    end
    
    def goal_execution_system_prompt
      <<~PROMPT
        You are an intelligent goal executor for a workflow system.
        
        Your job:
        1. Analyze the goal and available tools
        2. Create an efficient action plan
        3. Use available context data to inform your decisions
        4. Chain tools together when beneficial
        5. Be adaptive - if something fails, try a different approach
        
        Guidelines:
        - Prefer simpler solutions (fewer tools)
        - Use context data to avoid redundant operations
        - Consider tool dependencies and order
        - Be specific with tool arguments
        - Think step-by-step
        
        Always return valid JSON with your action plan.
      PROMPT
    end
  end
end
