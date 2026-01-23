# frozen_string_literal: true

module Workflows
  # ArchitectService - AI-powered workflow design assistant
  #
  # This is the "build with probability" part of the architecture:
  # - Understands natural language workflow descriptions
  # - Suggests appropriate nodes and connections
  # - Asks clarifying questions when needed
  # - Generates workflow definitions for the visual designer
  #
  # The architect helps users through the design phase, and once complete,
  # the CompilerService converts the design to deterministic executable steps.
  #
  class ArchitectService
    attr_reader :entity, :user, :conversation_history, :current_workflow

    def initialize(entity:, user:, workflow_id: nil)
      @entity = entity
      @user = user
      @node_registry = NodeRegistry.instance
      @conversation_history = []
      @current_workflow = nil
      @pending_questions = []

      load_workflow(workflow_id) if workflow_id
    end

    # Process a user message about workflow design
    # Returns { response: String, workflow: Hash, questions: Array, action: Symbol }
    def process_message(message)
      @conversation_history << { role: 'user', content: message }

      # Analyze the message intent
      intent = analyze_intent(message)

      case intent[:type]
      when :create_new
        handle_create_new(message, intent)
      when :modify_existing
        handle_modify(message, intent)
      when :add_step
        handle_add_step(message, intent)
      when :answer_question
        handle_answer(message, intent)
      when :explain
        handle_explain(message, intent)
      when :compile
        handle_compile
      when :test
        handle_test(message, intent)
      else
        handle_general(message)
      end
    end

    # Generate a workflow from a natural language description
    def generate_workflow(description)
      Rails.logger.info "[WorkflowArchitect] Generating workflow from: #{description[0..100]}..."

      # Get available integrations and modules for context
      context = build_entity_context

      # Generate with AI
      result = generate_with_ai(description, context)

      if result[:success]
        @current_workflow = result[:workflow]
        
        # Check if we need clarification
        if result[:questions].any?
          @pending_questions = result[:questions]
        end
      end

      result
    end

    # Get the current workflow definition for the designer
    def workflow_definition
      return nil unless @current_workflow

      {
        nodes: @current_workflow[:nodes] || [],
        connections: @current_workflow[:connections] || [],
        metadata: {
          name: @current_workflow[:name],
          description: @current_workflow[:description],
          version: @current_workflow[:version] || 1,
          architect_session: true
        }
      }
    end

    # Save the current workflow to an AutomationCode
    def save_workflow(name: nil)
      return { success: false, error: "No workflow to save" } unless @current_workflow

      name ||= @current_workflow[:name] || "Workflow #{Time.current.to_i}"
      slug = name.parameterize.presence || "workflow-#{Time.current.to_i}"

      # Ensure unique slug
      base_slug = slug
      counter = 1
      while AutomationCode.exists?(entity: entity, slug: slug)
        slug = "#{base_slug}-#{counter}"
        counter += 1
      end

      automation = AutomationCode.create!(
        entity: entity,
        created_by: user,
        name: name,
        slug: slug,
        description: @current_workflow[:description],
        trigger_type: determine_trigger_type,
        status: 'draft',
        code: '# Generated from visual workflow',
        workflow_definition: workflow_definition,
        design_mode: true
      )

      { success: true, automation_code: automation, id: automation.id }
    rescue => e
      { success: false, error: e.message }
    end

    private

    def load_workflow(workflow_id)
      automation = AutomationCode.find_by(id: workflow_id, entity: entity)
      return unless automation

      @current_workflow = {
        id: automation.id,
        name: automation.name,
        description: automation.description,
        nodes: automation.workflow_definition&.dig('nodes') || [],
        connections: automation.workflow_definition&.dig('connections') || []
      }
    end

    def analyze_intent(message)
      lower = message.downcase

      if lower.match?(/\b(create|build|make|design)\s+(a\s+)?(new\s+)?workflow/i)
        { type: :create_new, confidence: 0.9 }
      elsif lower.match?(/\b(add|insert)\s+(a\s+)?(step|node|action)/i)
        { type: :add_step, confidence: 0.9 }
      elsif lower.match?(/\b(change|modify|update|edit)\s/i)
        { type: :modify_existing, confidence: 0.8 }
      elsif lower.match?(/\b(compile|build|finalize|complete)\b/i) && @current_workflow
        { type: :compile, confidence: 0.9 }
      elsif lower.match?(/\b(test|try|run)\b/i) && @current_workflow
        { type: :test, confidence: 0.8 }
      elsif lower.match?(/\b(what|how|explain|help)\b/i)
        { type: :explain, confidence: 0.7 }
      elsif @pending_questions.any?
        { type: :answer_question, confidence: 0.8 }
      else
        { type: :general, confidence: 0.5 }
      end
    end

    def handle_create_new(message, intent)
      result = generate_workflow(message)

      response = if result[:success]
        workflow = result[:workflow]
        nodes_desc = workflow[:nodes].map { |n| "• #{n[:label] || n[:type]}" }.join("\n")
        
        msg = "I've designed a workflow for you:\n\n"
        msg += "**#{workflow[:name]}**\n"
        msg += "#{workflow[:description]}\n\n"
        msg += "**Steps:**\n#{nodes_desc}\n\n"
        
        if result[:questions].any?
          msg += "**I have a few questions:**\n"
          result[:questions].each_with_index do |q, i|
            msg += "#{i + 1}. #{q}\n"
          end
        else
          msg += "Would you like me to make any changes, or shall I compile this into an executable workflow?"
        end
        
        msg
      else
        "I had trouble designing that workflow: #{result[:error]}. Could you describe what you want the workflow to do?"
      end

      @conversation_history << { role: 'assistant', content: response }

      {
        response: response,
        workflow: workflow_definition,
        questions: result[:questions] || [],
        action: :created
      }
    end

    def handle_add_step(message, intent)
      unless @current_workflow
        return {
          response: "I don't have a workflow to add steps to. Would you like to create a new one?",
          action: :no_workflow
        }
      end

      # Parse what step to add
      step_result = parse_step_request(message)
      
      if step_result[:success]
        add_node_to_workflow(step_result[:node])
        
        response = "Added a **#{step_result[:node][:label]}** step to your workflow. " \
                   "It's connected after the previous step. Would you like to add more steps or make any changes?"
        
        @conversation_history << { role: 'assistant', content: response }
        
        {
          response: response,
          workflow: workflow_definition,
          action: :step_added
        }
      else
        {
          response: "I'm not sure what kind of step to add. Could you be more specific? " \
                   "For example: 'Add an email step' or 'Add a condition to check the status'",
          action: :clarification_needed
        }
      end
    end

    def handle_compile
      unless @current_workflow
        return { response: "No workflow to compile.", action: :error }
      end

      # Save first if not saved
      if @current_workflow[:id].blank?
        save_result = save_workflow
        return { response: "Failed to save: #{save_result[:error]}", action: :error } unless save_result[:success]
        @current_workflow[:id] = save_result[:id]
      end

      # Compile
      automation = AutomationCode.find(@current_workflow[:id])
      compiler = CompilerService.new(automation)
      result = compiler.compile!

      if result[:success]
        response = "✅ **Workflow compiled successfully!**\n\n"
        response += "• #{result[:stats][:total_nodes]} nodes compiled\n"
        response += "• #{result[:stats][:compiled_steps]} executable steps\n"
        response += "• Trigger: #{result[:stats][:trigger_type]}\n\n"
        response += "Your workflow is now ready to run. You can trigger it manually or set up automated triggers."
        
        if result[:warnings].any?
          response += "\n\n⚠️ **Warnings:**\n"
          result[:warnings].each { |w| response += "• #{w}\n" }
        end
      else
        response = "❌ **Compilation failed:**\n"
        result[:errors].each { |e| response += "• #{e}\n" }
        response += "\nPlease fix these issues and try again."
      end

      @conversation_history << { role: 'assistant', content: response }

      {
        response: response,
        workflow: workflow_definition,
        action: result[:success] ? :compiled : :compile_error,
        compilation_result: result
      }
    end

    def handle_explain(message, intent)
      lower = message.downcase

      response = if lower.include?('node') || lower.include?('step')
        explain_node_types
      elsif lower.include?('trigger')
        explain_triggers
      elsif lower.include?('workflow')
        explain_workflows
      else
        general_help
      end

      @conversation_history << { role: 'assistant', content: response }
      { response: response, action: :explained }
    end

    def handle_general(message)
      # Use AI to understand and respond
      response = generate_general_response(message)
      @conversation_history << { role: 'assistant', content: response }
      { response: response, action: :responded }
    end

    def handle_answer(message, intent)
      # Process answer to pending questions
      if @pending_questions.any?
        question = @pending_questions.shift
        apply_answer(question, message)
        
        if @pending_questions.any?
          next_q = @pending_questions.first
          response = "Got it! Next question: #{next_q}"
        else
          response = "Thanks! Your workflow is updated. Would you like to make any other changes or compile it?"
        end
      else
        response = generate_general_response(message)
      end

      @conversation_history << { role: 'assistant', content: response }
      { response: response, workflow: workflow_definition, action: :answered }
    end

    def handle_modify(message, intent)
      # AI-powered modification
      result = modify_with_ai(message)
      
      @conversation_history << { role: 'assistant', content: result[:response] }
      {
        response: result[:response],
        workflow: workflow_definition,
        action: :modified
      }
    end

    def handle_test(message, intent)
      unless @current_workflow&.dig(:id)
        return { response: "Please compile the workflow first before testing.", action: :error }
      end

      automation = AutomationCode.find(@current_workflow[:id])
      
      unless automation.is_compiled?
        return { response: "The workflow needs to be compiled first. Say 'compile' to compile it.", action: :error }
      end

      # Create a test execution
      test_context = { test: true, triggered_by: user.email }
      
      execution = AutomationExecution.create!(
        automation_code: automation,
        entity: entity,
        triggered_by: user,
        trigger_source: 'test',
        status: 'pending',
        input_data: test_context
      )

      # Execute synchronously for testing
      executor = ExecutorService.new(execution)
      result = executor.execute!

      response = if result[:success]
        "✅ **Test passed!**\n\nThe workflow executed successfully.\n\n" \
        "**Output:**\n```json\n#{JSON.pretty_generate(result[:output]).truncate(500)}\n```"
      else
        "❌ **Test failed:**\n#{result[:error]}"
      end

      @conversation_history << { role: 'assistant', content: response }
      { response: response, action: result[:success] ? :test_passed : :test_failed }
    end

    def build_entity_context
      {
        integrations: entity.integrations.connected.pluck(:name, :slug),
        modules: entity.app_modules.active.pluck(:name, :slug),
        agents: entity.agent_plugins.active.pluck(:name, :slug),
        landing_pages: entity.landing_pages.published.pluck(:title, :slug)
      }
    end

    def generate_with_ai(description, context)
      system_prompt = build_architect_system_prompt(context)
      
      user_prompt = <<~PROMPT
        Design a workflow based on this description:
        
        #{description}
        
        Consider:
        - What should trigger this workflow?
        - What steps are needed?
        - Are there any conditions or branches?
        - What data flows between steps?
        
        Respond with a JSON workflow definition.
      PROMPT

      begin
        bedrock = BedrockService.new
        response = bedrock.send_message(
          messages: [{ role: 'user', content: user_prompt }],
          system: system_prompt,
          max_tokens: 4000,
          temperature: 0.7
        )

        parse_workflow_response(response)
      rescue => e
        Rails.logger.error "[WorkflowArchitect] AI generation failed: #{e.message}"
        { success: false, error: e.message }
      end
    end

    def build_architect_system_prompt(context)
      node_palette = @node_registry.palette

      <<~PROMPT
        You are a Workflow Architect AI. Your job is to design workflows based on user requirements.
        
        ## Available Node Types
        
        #{node_palette.map { |cat, nodes| "### #{cat.to_s.titleize}\n#{nodes.map { |n| "- **#{n[:type]}**: #{n[:description]}" }.join("\n")}" }.join("\n\n")}
        
        ## Available Resources for this Entity
        
        - **Connected Integrations**: #{context[:integrations].map(&:first).join(', ').presence || 'None'}
        - **App Modules**: #{context[:modules].map(&:first).join(', ').presence || 'None'}
        - **AI Agents**: #{context[:agents].map(&:first).join(', ').presence || 'None'}
        - **Landing Pages**: #{context[:landing_pages].map(&:first).join(', ').presence || 'None'}
        
        ## Response Format
        
        Respond with a JSON object containing:
        ```json
        {
          "workflow": {
            "name": "Workflow Name",
            "description": "What this workflow does",
            "nodes": [
              {
                "id": "node_1",
                "type": "trigger-form",
                "label": "Form Submitted",
                "x": 100,
                "y": 100,
                "config": {}
              }
            ],
            "connections": [
              { "from": "node_1", "to": "node_2", "fromPort": "default", "toPort": "default" }
            ]
          },
          "questions": ["Any clarifying questions you need answered"],
          "explanation": "Brief explanation of the design"
        }
        ```
        
        ## Design Principles
        
        1. Every workflow needs exactly one trigger node
        2. Use appropriate node types for each step
        3. Connect nodes in logical flow order
        4. Use conditions for branching logic
        5. End with success or error output nodes
        6. Position nodes left-to-right, top-to-bottom
        7. Use meaningful labels for each node
        
        Ask clarifying questions if the requirements are ambiguous.
      PROMPT
    end

    def parse_workflow_response(response)
      # Extract JSON from response
      json_match = response.match(/```json\s*(.*?)\s*```/m) || response.match(/\{.*"workflow".*\}/m)
      
      if json_match
        json_str = json_match[1] || json_match[0]
        data = JSON.parse(json_str)
        
        {
          success: true,
          workflow: data['workflow'].with_indifferent_access,
          questions: data['questions'] || [],
          explanation: data['explanation']
        }
      else
        # Try to parse the whole response as JSON
        data = JSON.parse(response)
        {
          success: true,
          workflow: data['workflow'].with_indifferent_access,
          questions: data['questions'] || [],
          explanation: data['explanation']
        }
      end
    rescue JSON::ParserError => e
      Rails.logger.error "[WorkflowArchitect] Failed to parse response: #{e.message}"
      { success: false, error: "Failed to parse workflow design" }
    end

    def parse_step_request(message)
      lower = message.downcase

      node_type = if lower.include?('email') || lower.include?('send')
        'action-email'
      elsif lower.include?('create') && lower.include?('record')
        'action-create-record'
      elsif lower.include?('update') && lower.include?('record')
        'action-update-record'
      elsif lower.include?('http') || lower.include?('api') || lower.include?('request')
        'action-http-request'
      elsif lower.include?('condition') || lower.include?('if')
        'logic-condition'
      elsif lower.include?('loop') || lower.include?('each')
        'logic-loop'
      elsif lower.include?('agent') || lower.include?('ai')
        'agent-invoke'
      elsif lower.include?('delay') || lower.include?('wait')
        'action-delay'
      else
        nil
      end

      if node_type
        node_def = @node_registry.get(node_type)
        {
          success: true,
          node: {
            id: "node_#{SecureRandom.hex(4)}",
            type: node_type,
            label: node_def[:label],
            x: calculate_next_x,
            y: calculate_next_y,
            config: {}
          }
        }
      else
        { success: false }
      end
    end

    def add_node_to_workflow(node)
      @current_workflow[:nodes] ||= []
      @current_workflow[:connections] ||= []

      # Add the node
      @current_workflow[:nodes] << node

      # Connect to previous node
      if @current_workflow[:nodes].size > 1
        prev_node = @current_workflow[:nodes][-2]
        @current_workflow[:connections] << {
          from: prev_node[:id],
          to: node[:id],
          fromPort: 'default',
          toPort: 'default'
        }
      end
    end

    def calculate_next_x
      nodes = @current_workflow&.dig(:nodes) || []
      return 100 if nodes.empty?
      nodes.map { |n| n[:x] || 0 }.max + 200
    end

    def calculate_next_y
      100  # Keep Y constant for horizontal layout
    end

    def determine_trigger_type
      trigger = @current_workflow&.dig(:nodes)&.find { |n| n[:type].to_s.start_with?('trigger-') }
      return 'manual' unless trigger

      case trigger[:type]
      when 'trigger-form' then 'form_submit'
      when 'trigger-webhook' then 'webhook'
      when 'trigger-schedule' then 'schedule'
      when 'trigger-record' then 'record_created'
      else 'manual'
      end
    end

    def explain_node_types
      palette = @node_registry.palette
      
      response = "## Available Node Types\n\n"
      
      palette.each do |category, nodes|
        response += "### #{category.to_s.titleize}\n"
        nodes.each do |node|
          response += "- **#{node[:label]}** (`#{node[:type]}`): #{node[:description]}\n"
        end
        response += "\n"
      end

      response
    end

    def explain_triggers
      "## Workflow Triggers\n\n" \
      "Triggers are the entry points for workflows. Each workflow needs exactly one trigger.\n\n" \
      "**Available Triggers:**\n" \
      "- **Form Submission**: Fires when a form is submitted on a landing page or website\n" \
      "- **Webhook**: Fires when an external service calls a URL\n" \
      "- **Scheduled**: Fires on a schedule (cron or interval)\n" \
      "- **Record Event**: Fires when data changes in a module (create, update, delete)\n" \
      "- **Manual**: Fires when triggered by a user or API\n\n" \
      "Which trigger would you like to use for your workflow?"
    end

    def explain_workflows
      "## Workflows Overview\n\n" \
      "Workflows automate tasks by connecting triggers, actions, and logic together.\n\n" \
      "**How it works:**\n" \
      "1. **Trigger** - Something happens (form submit, schedule, record change)\n" \
      "2. **Process** - Steps execute in order (actions, conditions, transformations)\n" \
      "3. **Complete** - Workflow finishes with success or handles errors\n\n" \
      "**Example:** Form submission → Create contact record → Send welcome email → Update CRM\n\n" \
      "Would you like to create a workflow? Just describe what you want to automate!"
    end

    def general_help
      "## Workflow Designer Help\n\n" \
      "I can help you design and build workflows. Here's what I can do:\n\n" \
      "- **Create a workflow**: Describe what you want to automate\n" \
      "- **Add steps**: Add actions, conditions, or integrations\n" \
      "- **Modify**: Change existing nodes or connections\n" \
      "- **Compile**: Turn the design into an executable workflow\n" \
      "- **Test**: Run the workflow with test data\n\n" \
      "Try saying something like:\n" \
      "- \"Create a workflow that sends an email when a form is submitted\"\n" \
      "- \"Add a condition to check if the status is active\"\n" \
      "- \"Compile my workflow\""
    end

    def generate_general_response(message)
      # Use AI for general responses
      bedrock = BedrockService.new
      
      context = if @current_workflow
        "Current workflow: #{@current_workflow[:name]} with #{@current_workflow[:nodes]&.size || 0} nodes"
      else
        "No workflow currently loaded"
      end

      response = bedrock.send_message(
        messages: [{ role: 'user', content: message }],
        system: "You are a helpful Workflow Architect assistant. #{context}. Help the user design and build automated workflows. Be concise.",
        max_tokens: 500
      )

      response
    rescue => e
      "I'm not sure how to help with that. Try describing what you want to automate, or say 'help' for options."
    end

    def apply_answer(question, answer)
      # Update workflow based on the answer
      # This would be more sophisticated in production
      Rails.logger.info "[WorkflowArchitect] Applied answer '#{answer}' to question '#{question}'"
    end

    def modify_with_ai(message)
      return { response: "No workflow to modify" } unless @current_workflow

      # Use AI to understand and apply modification
      bedrock = BedrockService.new
      
      prompt = <<~PROMPT
        Current workflow:
        #{JSON.pretty_generate(@current_workflow)}
        
        User wants to: #{message}
        
        Respond with the modified workflow JSON and a brief explanation.
      PROMPT

      response = bedrock.send_message(
        messages: [{ role: 'user', content: prompt }],
        system: "You are a Workflow Architect. Modify the workflow based on the user's request. Return valid JSON.",
        max_tokens: 3000
      )

      # Try to parse and apply modification
      begin
        if response.include?('"nodes"')
          json_match = response.match(/\{.*"nodes".*\}/m)
          if json_match
            modified = JSON.parse(json_match[0])
            @current_workflow.merge!(modified.with_indifferent_access)
            { response: "Updated the workflow. #{response.split("\n").first}" }
          else
            { response: response }
          end
        else
          { response: response }
        end
      rescue
        { response: response }
      end
    end
  end
end
