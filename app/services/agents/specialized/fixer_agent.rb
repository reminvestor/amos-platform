module Agents
  module Specialized
    class FixerAgent < Agents::Base::BaseAgent
      MAX_FIX_ATTEMPTS = 5
      
      def initialize(task_session, initial_context = {})
        super(
          role: :fixer,
          capabilities: ['error_diagnosis', 'auto_repair', 'retry_logic'],
          context: initial_context,
          task_session: task_session
        )
        @ai_service = BedrockService.new
        @tool_catalog = ::Tools::ToolCatalog.instance
      end
      
      def system_prompt
        <<~PROMPT
          You are an expert AI Fixer Agent responsible for diagnosing and fixing workflow failures.
          
          Your responsibilities:
          1. Analyze error messages and failure contexts
          2. Understand what the step was trying to accomplish
          3. Use available tools to fix issues (data problems, missing resources, etc.)
          4. Retry operations with corrected parameters
          5. Know when a problem cannot be fixed and fail gracefully
          
          Available tools:
          #{available_tools_summary}
          
          Fixing principles:
          - Always understand the root cause before attempting a fix
          - Start with the simplest solution first
          - Use tools to inspect data and validate assumptions
          - Be creative in finding workarounds
          - Document what you tried for future learning
          - Know your limits - some problems require human intervention
          
          Common fixes:
          - Missing data: Use get_data to find alternatives
          - Invalid IDs: Search for the correct record
          - Schema mismatches: Use get_schema to understand structure
          - Missing relationships: Create them if possible
          - Data validation errors: Clean or transform the data
        PROMPT
      end
      
      def fix_failed_step(step, error_details, execution_context = {})
        Rails.logger.info "FixerAgent #{@id}: Attempting to fix step #{step[:id]} after error: #{error_details[:error]}"
        
        @execution_context = execution_context
        fix_attempts = 0
        
        while fix_attempts < MAX_FIX_ATTEMPTS
          fix_attempts += 1
          Rails.logger.info "FixerAgent #{@id}: Fix attempt #{fix_attempts}/#{MAX_FIX_ATTEMPTS}"
          
          # Analyze the problem
          analysis = analyze_failure(step, error_details, execution_context)
          
          if analysis[:unfixable]
            Rails.logger.error "FixerAgent #{@id}: Problem identified as unfixable: #{analysis[:reason]}"
            return {
              success: false,
              error: "Unfixable error: #{analysis[:reason]}",
              attempts: fix_attempts
            }
          end
          
          # Attempt to fix
          fix_result = attempt_fix(analysis, step, execution_context)
          
          if fix_result[:success]
            Rails.logger.info "FixerAgent #{@id}: Successfully fixed the issue!"
            return {
              success: true,
              result: fix_result[:result],
              fix_applied: fix_result[:fix_description],
              attempts: fix_attempts
            }
          end
          
          # Update error details for next attempt
          error_details = {
            error: fix_result[:error],
            previous_attempts: fix_attempts
          }
        end
        
        Rails.logger.error "FixerAgent #{@id}: Max fix attempts reached"
        {
          success: false,
          error: "Could not fix after #{MAX_FIX_ATTEMPTS} attempts",
          attempts: fix_attempts
        }
      end
      
      private
      
      def analyze_failure(step, error_details, context)
        prompt = build_analysis_prompt(step, error_details, context)
        
        response = @ai_service.complete(
          prompt: prompt,
          max_tokens: 1000,
          temperature: 0.3
        )
        
        analysis_data = extract_json_from_response(response)
        
        if analysis_data
          {
            problem_type: analysis_data['problem_type'],
            root_cause: analysis_data['root_cause'],
            fix_strategy: analysis_data['fix_strategy'],
            unfixable: analysis_data['unfixable'] || false,
            reason: analysis_data['unfixable_reason']
          }
        else
          {
            problem_type: 'unknown',
            root_cause: error_details[:error],
            fix_strategy: 'retry_with_diagnostics',
            unfixable: false
          }
        end
      rescue => e
        Rails.logger.error "FixerAgent analysis failed: #{e.message}"
        {
          problem_type: 'analysis_failure',
          root_cause: error_details[:error],
          fix_strategy: 'basic_retry',
          unfixable: false
        }
      end
      
      def attempt_fix(analysis, step, context)
        case analysis[:fix_strategy]
        when 'find_alternative_data'
          find_alternative_data(step, analysis, context)
        when 'create_missing_resource'
          create_missing_resource(step, analysis, context)
        when 'fix_data_format'
          fix_data_format(step, analysis, context)
        when 'retry_with_corrections'
          retry_with_corrections(step, analysis, context)
        when 'use_default_values'
          use_default_values(step, analysis, context)
        when 'ask_user_for_help'
          ask_user_for_help(step, analysis, context)
        else
          # Try a general fix approach
          general_fix_approach(step, analysis, context)
        end
      end
      
      def find_alternative_data(step, analysis, context)
        Rails.logger.info "FixerAgent: Searching for alternative data"
        
        # Example: If looking for a template that doesn't exist, find any template
        if step[:tool] == 'get_data' && step[:tool_args][:object_type] == 'email_templates'
          result = @tool_catalog.execute_tool(
            'get_data',
            {
              object_type: 'email_templates',
              limit: 1,
              order_by: 'created_at DESC'
            },
            build_tool_context
          )
          
          if result[:success] && result[:result][:count] > 0
            return {
              success: true,
              result: result[:result],
              fix_description: "Found alternative email template"
            }
          end
        end
        
        { success: false, error: "Could not find alternative data" }
      end
      
      def create_missing_resource(step, analysis, context)
        Rails.logger.info "FixerAgent: Creating missing resource"
        
        # Use AI to determine what needs to be created
        creation_prompt = <<~PROMPT
          The workflow step failed because a required resource is missing.
          Step: #{step.to_json}
          Error: #{analysis[:root_cause]}
          
          What resource should I create to fix this? Respond with JSON:
          {
            "resource_type": "type of resource",
            "creation_tool": "tool to use",
            "creation_args": { "tool arguments" }
          }
        PROMPT
        
        response = @ai_service.complete(
          prompt: creation_prompt,
          max_tokens: 500,
          temperature: 0.3
        )
        
        creation_data = extract_json_from_response(response)
        
        if creation_data && creation_data['creation_tool']
          result = @tool_catalog.execute_tool(
            creation_data['creation_tool'],
            creation_data['creation_args'],
            build_tool_context
          )
          
          if result[:success]
            return {
              success: true,
              result: result[:result],
              fix_description: "Created missing #{creation_data['resource_type']}"
            }
          end
        end
        
        { success: false, error: "Could not create missing resource" }
      end
      
      def retry_with_corrections(step, analysis, context)
        Rails.logger.info "FixerAgent: Retrying with corrections"
        
        # Ask AI for corrected parameters
        correction_prompt = <<~PROMPT
          The workflow step failed. Please provide corrected parameters.
          
          Original step: #{step.to_json}
          Error: #{analysis[:root_cause]}
          Context variables available: #{context[:workflow_execution]&.workflow_variables&.pluck(:name, :value)&.to_h}
          
          Provide corrected tool_args as JSON that will fix the issue:
        PROMPT
        
        response = @ai_service.complete(
          prompt: correction_prompt,
          max_tokens: 500,
          temperature: 0.3
        )
        
        corrected_args = extract_json_from_response(response)
        
        if corrected_args
          result = @tool_catalog.execute_tool(
            step[:tool],
            corrected_args,
            build_tool_context
          )
          
          if result[:success]
            return {
              success: true,
              result: result[:result],
              fix_description: "Retried with corrected parameters"
            }
          end
        end
        
        { success: false, error: "Retry with corrections failed" }
      end
      
      def general_fix_approach(step, analysis, context)
        Rails.logger.info "FixerAgent: Attempting general fix approach"
        
        # Ask AI to be creative in fixing the issue
        fix_prompt = <<~PROMPT
          A workflow step has failed and needs creative problem-solving.
          
          Step details: #{step.to_json}
          Error: #{analysis[:root_cause]}
          Available tools: #{@tool_catalog.all_tools.keys.join(', ')}
          
          You can use multiple tools to fix this. What sequence of tool calls would resolve this issue?
          
          Respond with JSON array of tool calls:
          [
            {
              "tool": "tool_name",
              "args": { "arguments" },
              "purpose": "what this accomplishes"
            }
          ]
        PROMPT
        
        response = @ai_service.complete(
          messages: [{ role: 'user', content: fix_prompt }],
          max_tokens: 1000,
          temperature: 0.5
        )
        
        tool_sequence = extract_json_from_response(response)
        
        if tool_sequence.is_a?(Array)
          last_result = nil
          
          tool_sequence.each do |tool_call|
            Rails.logger.info "FixerAgent: Executing #{tool_call['tool']} - #{tool_call['purpose']}"
            
            result = @tool_catalog.execute_tool(
              tool_call['tool'],
              tool_call['args'],
              build_tool_context
            )
            
            if result[:success]
              last_result = result[:result]
            else
              Rails.logger.warn "FixerAgent: Tool #{tool_call['tool']} failed: #{result[:error]}"
            end
          end
          
          if last_result
            return {
              success: true,
              result: last_result,
              fix_description: "Applied creative fix sequence"
            }
          end
        end
        
        { success: false, error: "General fix approach failed" }
      end
      
      def ask_user_for_help(step, analysis, context)
        Rails.logger.info "FixerAgent: Asking user for help with failed step"
        
        # Generate a conversational message explaining the issue
        user_prompt = generate_user_help_prompt(step, analysis)
        
        # Send through progress callback for display in chat
        context[:progress_callback]&.call({
          type: 'content_chunk',
          content: user_prompt
        })
        
        # Return a special status indicating user input is needed
        {
          status: 'awaiting_input',
          conversational: true,
          fix_context: {
            step_id: step[:id],
            analysis: analysis,
            original_error: analysis[:root_cause]
          },
          message: user_prompt,
          awaiting_user_response: true
        }
      end
      
      def generate_user_help_prompt(step, analysis)
        prompt = "I encountered an issue and need your help:\n\n"
        
        # Explain what we were trying to do
        prompt += "**What I was trying to do:**\n"
        prompt += "#{step[:config][:description] || step[:id]}\n\n"
        
        # Explain the problem
        prompt += "**The issue:**\n"
        prompt += "#{analysis[:root_cause]}\n\n"
        
        # Suggest what the user can do
        prompt += "**How you can help:**\n"
        
        case analysis[:problem_type]
        when 'missing_data'
          prompt += "• Please provide the missing information\n"
          prompt += "• Or tell me to skip this step\n"
          prompt += "• Or suggest an alternative approach\n"
        when 'permission_denied'
          prompt += "• Please check your permissions or credentials\n"
          prompt += "• Or provide alternative access method\n"
          prompt += "• Or tell me to proceed without this step\n"
        when 'resource_not_found'
          prompt += "• Please create the required resource first\n"
          prompt += "• Or provide an alternative resource to use\n"
          prompt += "• Or tell me how to proceed without it\n"
        else
          prompt += "• Please provide more information\n"
          prompt += "• Or suggest how to work around this issue\n"
          prompt += "• Or tell me to skip this step\n"
        end
        
        prompt += "\nWhat would you like me to do?"
        prompt
      end
      
      def build_analysis_prompt(step, error_details, context)
        <<~PROMPT
          Analyze this workflow step failure:
          
          Step Configuration:
          #{JSON.pretty_generate(step)}
          
          Error Details:
          #{error_details[:error]}
          
          Workflow Context:
          - Current variables: #{context[:workflow_execution]&.workflow_variables&.pluck(:name, :value)&.to_h}
          - Previous steps completed: #{context[:completed_steps]&.join(', ')}
          
          Analyze the problem and respond with JSON:
          {
            "problem_type": "missing_data|invalid_reference|schema_mismatch|permission_error|other",
            "root_cause": "detailed explanation of what went wrong",
            "fix_strategy": "find_alternative_data|create_missing_resource|fix_data_format|retry_with_corrections|use_default_values|ask_user_for_help",
            "unfixable": false,
            "unfixable_reason": null
          }
          
          Set unfixable to true only if:
          - The error requires human intervention
          - The system lacks permissions
          - The requested operation is impossible
        PROMPT
      end
      
      def build_tool_context
        # Safely extract workflow_execution_id
        workflow_exec = @execution_context[:workflow_execution]
        workflow_exec_id = if workflow_exec.respond_to?(:id)
          workflow_exec.id
        elsif workflow_exec.is_a?(Hash)
          workflow_exec[:id] || workflow_exec['id']
        else
          nil
        end
        
        # Safely extract task_session_id
        task_session_id = if @task_session.respond_to?(:id)
          @task_session.id
        elsif @task_session.is_a?(Hash)
          @task_session[:id] || @task_session['id']
        else
          nil
        end
        
        # Safely extract user and entity
        user = @execution_context[:user]
        user = user.is_a?(Hash) ? nil : user  # Skip if hash, needs to be object
        
        entity = @execution_context[:entity]
        entity = entity.is_a?(Hash) ? nil : entity  # Skip if hash, needs to be object
        
        {
          user: user || @task_session&.user,
          entity: entity || @task_session&.user&.entity,
          context: {
            task_session_id: task_session_id,
            workflow_execution_id: workflow_exec_id,
            fixer_agent_id: @id
          }
        }
      end
      
      def extract_json_from_response(response)
        # Handle response that might have markdown code blocks
        json_match = response.match(/```json\n(.*?)\n```/m)
        if json_match
          JSON.parse(json_match[1])
        else
          # Try parsing the whole response as JSON
          JSON.parse(response)
        end
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse JSON from response: #{e.message}"
        nil
      end
      
      def use_default_values(step, analysis, context)
        Rails.logger.info "FixerAgent: Using default values approach"
        
        # For certain operations, we can provide sensible defaults
        case step[:tool]
        when 'create_object'
          # Add default values for missing required fields
          default_args = step[:tool_args].deep_dup
          
          # Get schema to know required fields
          schema_result = @tool_catalog.execute_tool(
            'get_schema',
            { object_type: step[:tool_args][:object_type] },
            build_tool_context
          )
          
          if schema_result[:success]
            required_fields = schema_result[:result][:schema][:required_fields] || []
            
            required_fields.each do |field|
              unless default_args[:data][field]
                # Provide sensible defaults
                default_args[:data][field] = case field
                when /name|title/
                  "Default #{step[:tool_args][:object_type].singularize.titleize}"
                when /description/
                  "Automatically created by workflow"
                when /status/
                  'draft'
                else
                  ''
                end
              end
            end
            
            result = @tool_catalog.execute_tool(
              step[:tool],
              default_args,
              build_tool_context
            )
            
            if result[:success]
              return {
                success: true,
                result: result[:result],
                fix_description: "Used default values for missing fields"
              }
            end
          end
        end
        
        { success: false, error: "Could not apply default values" }
      end
      
      def available_tools_summary
        tools = @tool_catalog.get_tools_for_role('fixer')
        tools.map { |tool| "- #{tool.name}: #{tool.description}" }.join("\n")
      end
    end
  end
end
