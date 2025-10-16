module Agents
  class GoalExecutor < PhaseExecutor
    def execute
      phase_id = @phase[:id] || @phase["id"]
      goal = @phase[:goal] || @phase["goal"]

      Rails.logger.info "🎯 GoalExecutor: Starting phase #{phase_id}"
      Rails.logger.info "🎯 Goal: #{goal}"

      notify_progress("Working on: #{goal}")

      # Get execution strategy
      strategy = @phase[:execution_strategy] || @phase["execution_strategy"] || {}
      approach = strategy[:approach] || strategy["approach"] || "adaptive"

      # Get constraints
      constraints = strategy[:constraints] || strategy["constraints"] || {}

      # Get allowed tools
      allowed_tools = strategy[:allowed_tools] || strategy["allowed_tools"] || []

      # Get AI instructions
      ai_instructions = @phase[:ai_instructions] || @phase["ai_instructions"]

      # Get required data from previous phases
      required_data = gather_required_data

      case approach.to_s
      when "adaptive"
        execute_adaptively(goal, allowed_tools, constraints, ai_instructions, required_data)
      when "prescribed"
        execute_prescribed(strategy)
      when "structured"
        execute_structured(@phase)
      else
        execute_adaptively(goal, allowed_tools, constraints, ai_instructions, required_data)
      end
    end

    private

    def gather_required_data
      requires = @phase[:requires_from_previous] || @phase["requires_from_previous"] || []
      data = {}
      
      # Reload workflow contexts to ensure we have latest data from previous phase
      if @workflow_execution
        @workflow_execution.workflow_contexts.reload
      end

      context_data = get_workflow_context

      Rails.logger.info "📊 Raw context data from DB: #{context_data.keys.join(', ')}"


      # Include ALL context data (prefixed and unprefixed versions)
      data = context_data.dup

      # Create unprefixed versions for easier access
      context_data.each do |key, value|
        # If key has phase prefix like "gather_context_company_name"
        if key.to_s.match(/^(gather_context|extract)_(.+)/)
          unprefixed_key = $2
          data[unprefixed_key] = value unless data.key?(unprefixed_key)
          Rails.logger.info "  📍 Mapped #{key} → #{unprefixed_key}"
        end
      end

      Rails.logger.info "📋 Gathered data keys: #{data.keys.join(', ')}"
      Rails.logger.info "📋 Sample value: company_name=#{data['company_name']}"
      data
    end

    def execute_adaptively(goal, allowed_tools, constraints, ai_instructions, required_data)
      # Debug: log the context data available
      context_data = get_workflow_context
      Rails.logger.info "🔍 GoalExecutor context data: #{context_data.inspect}"
      Rails.logger.info "🔍 Required data: #{required_data.inspect}"

      max_attempts = @phase.dig(:adaptive, :max_attempts) ||
                    @phase.dig("adaptive", "max_attempts") || 3

      attempt = 0
      result = nil

      while attempt < max_attempts
        attempt += 1
        Rails.logger.info "🔄 Attempt #{attempt} of #{max_attempts}"

        # Let AI generate action plan for ALL goals (no hardcoding)
        action_plan = get_ai_action_plan(goal, allowed_tools, required_data, ai_instructions, attempt)

        Rails.logger.info "📋 AI Action Plan: #{action_plan.inspect}"

        # Execute the plan
        result = execute_action_plan(action_plan, constraints)

        # Check success criteria
        Rails.logger.info "🔍 Checking success criteria for result: #{result.dig(:data)&.keys || 'no data'}"

        if meets_success_criteria?(result)
          Rails.logger.info "✅ Goal achieved!"

          # Store result in workflow context
          store_phase_output(result[:data] || {}, "step_output")

          notify_progress("Goal achieved: #{goal}", type: "phase_complete")

          return {
            success: true,
            status: "completed",
            data: result[:data],
            phase: @phase[:id] || @phase["id"],
            attempts: attempt
          }
        else
          Rails.logger.warn "⚠️ Attempt #{attempt} did not meet success criteria"
          Rails.logger.warn "🔍 Result data: #{result.dig(:data)&.inspect}"
          Rails.logger.warn "🔍 Success criteria: #{@phase.dig(:execution_strategy, :success_when) || @phase.dig('execution_strategy', 'success_when')}"

          # Store the error for next attempt so AI can learn
          @last_attempt_error = result[:error] || "Action plan did not achieve goal"
          @last_attempt_results = result[:results] || []

          # If self-healing is enabled and this isn't the last attempt
          # Temporarily disabled - FixerAgent has initialization issues
          if false && should_attempt_fix?(attempt, max_attempts)
            notify_progress("Attempting to fix issues...", type: "self_healing")
            result = attempt_self_healing(result, goal)

            if result[:success]
              store_phase_output(result[:data] || {}, "step_output")
              notify_progress("Goal achieved after self-healing!", type: "phase_complete")

              return {
                success: true,
                status: "completed",
                data: result[:data],
                phase: @phase[:id] || @phase["id"],
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
        status: "failed",
        error: "Could not achieve goal after #{max_attempts} attempts",
        phase: @phase[:id] || @phase["id"],
        partial_result: result
      }
    end

    def get_ai_action_plan(goal, allowed_tools, required_data, ai_instructions, attempt)
      # Get available object types from registry
      available_types = ScoutDataRegistry.available_object_types rescue [ "campaigns", "contacts", "email_templates", "contact_groups", "landing_pages" ]

      prompt = <<~PROMPT
        You need to achieve this goal: #{goal}

        Available Tools:
        #{allowed_tools.map { |t| "- #{t}" }.join("\n")}

        Available Object Types in System:
        #{available_types.join(', ')}

        Object Type Format Rules:
        - get_schema: SINGULAR ("campaign", "email_template", "contact")
        - create_object: PLURAL ("campaigns", "email_templates", "contacts")
        - update_object: SINGULAR ("campaign", "email_template", "contact")

        Available Data from Previous Phases:
        #{JSON.pretty_generate(required_data)}

        Available Context:
        #{JSON.pretty_generate(get_workflow_context)}

        CRITICAL: When calling tools, use the ACTUAL VALUES from the context above!
        Examples:
        - If context has company_name: "TechCorp", use {"title": "TechCorp"}#{' '}
        - If context has value_proposition: "We help businesses save time", use that exact text
        - DO NOT use placeholders like "<company_name>" or generic values like "Landing Page"

        Instructions:
        #{ai_instructions}

        This is attempt #{attempt}.#{' '}
        #{if attempt > 1 && @last_attempt_error
          "Previous attempt failed: #{@last_attempt_error}\n" +
          "Previous results: #{@last_attempt_results.map { |r| "#{r[:tool]}: #{r[:success] ? 'success' : r[:result][:error] || 'failed'}" }.join(', ')}\n" +
          "Learn from these errors and create a corrected plan!"
          else
          ""
          end}

        CRITICAL: Create a COMPLETE action plan that FULLY achieves the goal.

        Your action plan must:
        1. Include ALL steps from start to finish (not just discovery)
        2. Use creation tools (create_object, update_object, generate_*) not just read tools
        3. Chain tools in the correct order (e.g., get_schema THEN create_object)
        4. Use gathered data to populate tool arguments

        VARIABLE REFERENCE SYNTAX (for chaining actions):
        To reference results from previous actions, use this EXACT format:
        {{actions[INDEX].result.id}}

        Example: If action 1 creates a template, reference it as:
        "email_template_id": "{{actions[1].result.id}}"

        DO NOT use:
        - {{create_object_1.id}} (wrong)
        - {{actions.1.result.id}} (wrong - use brackets not dots)
        - {{template_id}} (ambiguous)
        - {{created_template_id}} (ambiguous)

        ALWAYS use: {{actions[INDEX].result.id}} where INDEX is 0-based

        BAD EXAMPLE (incomplete):
        {
          "approach": "single_tool",
          "actions": [
            {"tool": "get_schema", "args": {...}}
          ]
        }
        This only retrieves schema but doesn't CREATE anything!

        GOOD EXAMPLE (complete with variable chaining):
        {
          "approach": "tool_chain",
          "actions": [
            {"tool": "create_object", "args": {"object_type": "email_templates", "data": {"name": "Template Name", "subject": "Subject", "body": "Content"}}},
            {"tool": "create_object", "args": {"object_type": "campaigns", "data": {"name": "Campaign", "status": "draft", "scheduled_at": "2025-12-31", "email_template_id": "{{actions[0].result.id}}"}}}
          ]
        }
        This creates template (action 0), then creates campaign WITH template_id!

        CRITICAL RULES:
        - get_schema uses SINGULAR: "email_template", "campaign", "contact"
        - create_object uses PLURAL: "email_templates", "campaigns", "contacts"
        - If get_schema says object is "email_template", create_object needs "email_templates" (add 's')
        - If schema shows field "body", use "body" not "content"

        Respond with JSON:
        {
          "approach": "single_tool|tool_chain",
          "reasoning": "why this complete plan will achieve the goal",
          "actions": [
            {
              "tool": "tool_name",
              "args": { "arg1": "value1" },
              "description": "what this tool does"
            }
          ]
        }
      PROMPT

      result = ai_decide(prompt,
        expect_json: true,
        system_prompt: goal_execution_system_prompt,
        max_tokens: 2000
      )

      Rails.logger.info "🔍 RAW AI RESPONSE: #{result.inspect}"
      result
    end

    def execute_action_plan(plan, constraints)
      return { success: false, error: "Invalid plan" } unless plan.is_a?(Hash)

      # Handle both formats: single action OR actions array
      actions = if plan["actions"]
                  plan["actions"]
      elsif plan["tool"]
                  # Single action format
                  [ {
                    "tool" => plan["tool"],
                    "args" => plan["args"] || {},
                    "description" => plan["description"]
                  } ]
      else
                  []
      end

      return { success: false, error: "No actions in plan" } if actions.empty?

      results = []

      # Check constraints
      if constraints["max_ai_calls"] && actions.length > constraints["max_ai_calls"]
        return {
          success: false,
          error: "Plan exceeds max_ai_calls constraint (#{constraints['max_ai_calls']})"
        }
      end

      # Execute each action
      actions.each_with_index do |action, index|
        tool_name = action["tool"]
        tool_args = action["args"] || {}

        Rails.logger.info "🔧 Executing action #{index + 1}: #{tool_name}"
        notify_progress("#{action['description'] || "Using #{tool_name}"}...", type: "tool_start", tool_name: tool_name)

        # Resolve any variable references in args using previous results
        resolved_args = resolve_tool_args(tool_args, results)

        # Execute the tool
        result = execute_tool(tool_name, resolved_args)

        notify_progress("Completed: #{tool_name}", type: "tool_complete", tool_name: tool_name)

        results << {
          tool: tool_name,
          args: resolved_args,
          result: result,
          success: result[:success] || result["success"]
        }

        # Stop if a tool fails (unless chaining is allowed)
        unless result[:success] || result["success"]
          Rails.logger.error "❌ Tool #{tool_name} failed: #{result[:error] || result['error']}"
          return {
            success: false,
            error: result[:error] || result["error"] || "Tool #{tool_name} failed",
            results: results
          }
        end

        Rails.logger.info "✅ Action #{index + 1} completed successfully"
      end

      Rails.logger.info "🎯 All #{actions.length} actions executed successfully"

      # Combine all results
      combined_data = results.reduce({}) do |acc, r|
        tool_result = r[:result]
        if tool_result.is_a?(Hash)
          acc.merge!(tool_result)
        end
        acc
      end

      Rails.logger.info "📦 Combined data keys: #{combined_data.keys.join(', ')}"

      {
        success: true,
        data: combined_data,
        results: results,
        actions_executed: actions.length
      }
    end

    def resolve_tool_args(args, previous_results = [])
      return args unless args.is_a?(Hash)

      resolved = args.deep_dup
      context_data = get_workflow_context

      resolved.each do |key, value|
        if value.is_a?(String) && value.match?(/\{\{(.+?)\}\}/)
          # Replace {{variable}} with actual value
          value.scan(/\{\{(.+?)\}\}/).each do |match|
            var_name = match[0].strip

            # Try to resolve from previous action results
            # Handle multiple patterns:
            # - {{actions[1].result.id}} or {{actions[1].id}}
            # - {{action_1_result.id}} or {{action_1.id}}
            # - {{created_template_id}} or {{template_id}} or {{campaign_id}}

            # Pattern 1: actions[N], actions.N, or action_N
            if var_name.match?(/actions?[\.\[](\d+)/)
              action_index = var_name.match(/[\.\[](\d+)/)[1].to_i

              if previous_results[action_index]
                action_result = previous_results[action_index][:result]
                resolved_value = action_result[:id] || action_result["id"]

                if resolved_value
                  resolved[key] = value.gsub("{{#{var_name}}}", resolved_value.to_s)
                  Rails.logger.info "✅ Resolved {{#{var_name}}} to #{resolved_value} (from action #{action_index})"
                  next
                end
              end
            # Pattern 1b: create_object_N, get_data_N (Nth occurrence of that tool)
            elsif var_name.match?(/^(create_object|get_data|update_object)_(\d+)/)
              tool_type = var_name.match(/^([a-z_]+)_(\d+)/)[1]
              occurrence = var_name.match(/^([a-z_]+)_(\d+)/)[2].to_i

              # Find the Nth occurrence of this tool type
              matching_results = previous_results.select { |r| r[:tool] == tool_type }

              if matching_results[occurrence]
                result_data = matching_results[occurrence][:result]
                resolved_value = result_data[:id] || result_data["id"]

                if resolved_value
                  resolved[key] = value.gsub("{{#{var_name}}}", resolved_value.to_s)
                  Rails.logger.info "✅ Resolved {{#{var_name}}} to #{resolved_value} (#{occurrence}th #{tool_type})"
                  next
                end
              end
            # Pattern 2: created_X_id, X_id (find most recent matching object)
            elsif var_name.match?(/_id$/)
              # Extract object type from variable name: created_template_id → template
              object_hint = var_name.gsub(/^created_/, "").gsub(/_id$/, "")

              # Search backwards through results for matching type
              previous_results.reverse_each.with_index do |result_entry, reverse_idx|
                tool_name = result_entry[:tool]
                result_data = result_entry[:result]

                # Check if this looks like the right object type
                if tool_name == "create_object" || result_data[:object_type]&.include?(object_hint)
                  resolved_value = result_data[:id] || result_data["id"]

                  if resolved_value
                    actual_index = previous_results.length - 1 - reverse_idx
                    resolved[key] = value.gsub("{{#{var_name}}}", resolved_value.to_s)
                    Rails.logger.info "✅ Resolved {{#{var_name}}} to #{resolved_value} (from action #{actual_index} by object type)"
                    break
                  end
                end
              end
              next if resolved[key] != value # Skip context lookup if we resolved it
            end

            # Fall back to workflow context
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
          resolved[key] = resolve_tool_args(value, previous_results)
        elsif value.is_a?(Array)
          resolved[key] = value.map { |v| v.is_a?(Hash) ? resolve_tool_args(v, previous_results) : v }
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
                        @phase.dig("execution_strategy", "success_when") || {}

      # If no explicit criteria and no actions were executed, this is not success
      if success_criteria.empty?
        # Check if any meaningful action was taken (not just schema/data retrieval)
        actions_executed = result[:actions_executed] || 0
        results = result[:results] || []

        # If only read-only tools were used (get_schema, get_data), this is incomplete
        read_only_tools = [ "get_schema", "get_data", "get_workflow_context" ]
        all_readonly = results.all? { |r| read_only_tools.include?(r[:tool]) }

        if all_readonly
          Rails.logger.info "⚠️ Only read-only tools executed, goal not achieved yet"
          return false
        end

        # Default: any successful tool result
        return result[:success]
      end

      # Generic check for any criterion
      # If criterion name ends with "_exists", check if that key exists in data
      # Otherwise, just ensure expected_value matches
      success_criteria.all? do |criterion, expected_value|
        Rails.logger.info "🔍 Checking criterion: #{criterion} = #{expected_value}"
        criterion_str = criterion.to_s

        if criterion_str.end_with?("_exists") || criterion_str.end_with?("_id_exists")
          # Check if ANY id was returned (generic for all object types)
          has_id = result.dig(:data, "id").present? ||
                   result.dig(:data, :id).present?
          Rails.logger.info "  → ID present: #{has_id}"
          has_id
        elsif criterion_str == "created" || criterion_str == "updated"
          # Check if operation returned created/updated flag
          was_created = result.dig(:data, "created") || result.dig(:data, :created) ||
                       result.dig(:data, "updated") || result.dig(:data, :updated) ||
                       result.dig(:data, "id").present?
          Rails.logger.info "  → Operation successful: #{was_created}"
          was_created
        else
          # Generic check - just verify result succeeded
          check_result = result[:success] == true
          Rails.logger.info "  → Generic success check: #{check_result}"
          check_result
        end
      end
    end

    def should_attempt_fix?(attempt, max_attempts)
      return false if attempt >= max_attempts

      self_healing_enabled = @phase.dig(:adaptive, :self_healing) ||
                            @phase.dig("adaptive", "self_healing")

      self_healing_enabled != false
    end

    def attempt_self_healing(failed_result, goal)
      Rails.logger.info "🔧 Attempting self-healing..."

      # Use FixerAgent if available
      fixer = Agents::Specialized::FixerAgent.new(
        @context[:task_session],
        @context
      )

      fix_context = {
        phase_id: @phase[:id] || @phase["id"],
        goal: goal,
        failed_result: failed_result,
        available_tools: @phase.dig(:execution_strategy, :allowed_tools) ||
                        @phase.dig("execution_strategy", "allowed_tools")
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

    def execute_structured(phase)
      Rails.logger.info "🏗️ Executing structured goal with data mapping"

      # Get data mapping from phase
      data_mapping = phase[:data_mapping] || phase["data_mapping"]
      unless data_mapping
        Rails.logger.error "No data_mapping found in phase!"
        return execute_adaptively(
          phase[:goal] || phase["goal"],
          phase.dig(:execution_strategy, :allowed_tools) || [],
          phase.dig(:execution_strategy, :constraints) || {},
          phase[:ai_instructions] || phase["ai_instructions"],
          gather_required_data
        )
      end

      # Get tool name and args template
      tool_name = data_mapping[:tool] || data_mapping["tool"]
      args_template = data_mapping[:args] || data_mapping["args"]

      Rails.logger.info "📋 Tool: #{tool_name}"
      Rails.logger.info "📋 Args template: #{args_template.inspect}"

      # Get all context data
      context_data = gather_required_data
      Rails.logger.info "📊 Available context data: #{context_data.inspect}"

      # Resolve the template with actual values
      resolved_args = resolve_template(args_template, context_data)
      Rails.logger.info "✅ Resolved args: #{resolved_args.inspect}"

      # Execute the tool directly
      result = execute_tool(tool_name, resolved_args)

      if result[:success]
        Rails.logger.info "✅ Structured execution successful!"

        # Extract operation message if available (for idempotent operations)
        operation_msg = result[:result]&.dig("operation_message") ||
                       result[:result]&.dig(:operation_message) ||
                       result[:message] || result["message"]

        # Store the result data - tools return data directly, not nested in [:result]
        data_to_store = result[:data] || result["data"] || result.except(:success, :message, "success", "message")
        Rails.logger.info "📦 Storing phase output: #{data_to_store.keys.join(', ')}"
        store_phase_output(data_to_store, "step_output")

        # Use specific message if available, otherwise generic success
        success_msg = operation_msg || "Goal achieved!"
        notify_progress(success_msg, type: "phase_complete")

        {
          success: true,
          status: "completed",
          data: data_to_store,
          phase: phase[:id] || phase["id"],
          message: success_msg
        }
      else
        Rails.logger.error "❌ Structured execution failed: #{result[:error]}"
        {
          success: false,
          status: "failed",
          error: result[:error],
          phase: phase[:id] || phase["id"]
        }
      end
    end

    def resolve_template(template, context_data)
      if template.is_a?(Hash)
        resolved = {}
        template.each do |key, value|
          resolved[key] = resolve_template(value, context_data)
        end
        resolved
      elsif template.is_a?(Array)
        template.map { |item| resolve_template(item, context_data) }
      elsif template.is_a?(String) && template.match?(/\{\{(.+?)\}\}/)
        # Replace {{variable}} with actual value
        result = template.dup
        template.scan(/\{\{(.+?)\}\}/).each do |match|
          var_name = match[0].strip

          # Try exact match first
          value = context_data[var_name] || context_data[var_name.to_sym]

          # Try with gather_context prefix
          if value.nil?
            prefixed_key = "gather_context_#{var_name}"
            value = context_data[prefixed_key] || context_data[prefixed_key.to_sym]
          end

          if value
            result = result.gsub("{{#{var_name}}}", value.to_s)
            Rails.logger.info "📌 Resolved {{#{var_name}}} => #{value}"
          else
            Rails.logger.warn "⚠️ Could not resolve {{#{var_name}}}"
            # Return empty string instead of template
            result = result.gsub("{{#{var_name}}}", "")
          end
        end
        result
      else
        template
      end
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

        IMPORTANT: Use the actual values from context_data when calling tools!
        For example, if context_data contains company_name: "Acme Corp",#{' '}
        use "Acme Corp" in your tool arguments, not placeholders.

        Always return valid JSON with your action plan.
      PROMPT
    end
  end
end
