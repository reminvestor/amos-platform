# frozen_string_literal: true

class ExecuteScheduledAgentTaskJob < ApplicationJob
  queue_as :agents
  
  # Retry with exponential backoff
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  
  def perform(scheduled_task_id)
    @scheduled_task = ScheduledAgentTask.find(scheduled_task_id)
    
    # Check if task can run (includes token balance check)
    unless @scheduled_task.can_run?
      Rails.logger.info "⏸️ Scheduled task #{@scheduled_task.id} cannot run (disabled, expired, or insufficient tokens)"
      
      # If blocked due to tokens, auto-pause the task to prevent repeated attempts
      unless @scheduled_task.has_sufficient_tokens?
        Rails.logger.warn "🚫 Auto-pausing scheduled task #{@scheduled_task.id} due to insufficient tokens"
        @scheduled_task.update(status: 'paused', metadata: @scheduled_task.metadata.merge(
          'paused_reason' => 'insufficient_tokens',
          'paused_at' => Time.current.iso8601
        ))
        
        # Notify user
        UserNotification.create(
          user: @scheduled_task.user,
          entity: @scheduled_task.entity,
          notification_type: 'task_paused',
          title: "⏸️ Scheduled task paused",
          body: "Your scheduled task '#{@scheduled_task.name}' has been paused due to insufficient token balance. Please purchase tokens to resume.",
          priority: 'high',
          action_url: "/billing",
          action_type: 'view'
        ) rescue nil
      end
      
      return
    end
    
    Rails.logger.info "🕐 Executing scheduled task: #{@scheduled_task.name} (#{@scheduled_task.id})"
    
    # Create a run record
    @run = @scheduled_task.scheduled_task_runs.create!(
      user: @scheduled_task.user,
      status: 'pending'
    )
    
    begin
      @run.start!
      
      # Execute based on execution mode
      result = case @scheduled_task.execution_mode
      when 'agent_only'
        execute_agent_only
      when 'tool_only'
        execute_tool_only
      else
        # Default: Scout decides what to do
        if @scheduled_task.agent_plugin.present?
          execute_with_agent
        else
          execute_with_scout
        end
      end
      
      # Process the result
      process_result(result)
      
    rescue => e
      Rails.logger.error "❌ Scheduled task failed: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      @run.fail!(e.message)
      
      # Create failure notification
      create_failure_notification(e)
      
      raise # Re-raise for retry logic
    end
  end
  
  private
  
  def execute_with_scout
    user = @scheduled_task.user
    entity = @scheduled_task.entity
    session_id = "scheduled-#{@scheduled_task.id}-#{Time.current.to_i}"
    
    # Build the prompt with any additional context
    prompt = build_prompt
    
    # Use V3 agent loop
    agent = V3::AgentLoop.new(
      user: user,
      entity: entity,
      session_id: session_id,
      model: ENV.fetch("BEDROCK_DEFAULT_MODEL", "anthropic.claude-sonnet-4-v1")
    )
    
    # Collect results from streaming
    accumulated_content = ""
    
    result = agent.process_message_streaming(
      prompt,
      ->(chunk) {
        if chunk.is_a?(Hash) && chunk[:type] == :content && chunk[:text].present?
          accumulated_content += chunk[:text]
        end
      },
      [],  # no conversation history for scheduled tasks
      nil  # no canvas
    )
    
    final_response = result.dig(:final_response, :message) || accumulated_content
    
    {
      content: final_response,
      canvas_data: result[:canvas_data],
      tools_used: result[:tools_used] || [],
      session_id: session_id
    }
  end
  
  # Execute with a specific agent ONLY - deterministic mode
  def execute_agent_only
    agent = @scheduled_task.required_agent || @scheduled_task.agent_plugin
    
    unless agent
      if @scheduled_task.allow_fallback?
        Rails.logger.warn "⚠️ Required agent not found, falling back to Scout"
        return execute_with_scout
      else
        raise "Required agent '#{@scheduled_task.required_agent_slug}' not found and fallback disabled"
      end
    end
    
    Rails.logger.info "🤖 Executing with agent ONLY: #{agent.name} (deterministic mode)"
    
    user = @scheduled_task.user
    entity = @scheduled_task.entity
    
    # Create an execution record
    execution = AgentPluginExecution.create!(
      agent_plugin: agent,
      user: user,
      status: 'running',
      input_context: {
        prompt: build_prompt,
        scheduled_task_id: @scheduled_task.id,
        deterministic_mode: true,
        **(@scheduled_task.input_context.except('execution_mode', 'required_agent_slug', 'required_tools', 'allow_fallback'))
      }
    )
    
    # Link the run to the execution
    @run.update!(agent_plugin_execution: execution)
    
    # Execute the agent directly
    executor = Agents::StandardPluginExecutor.new(agent, {
      entity: entity,
      user: user,
      agent_plugin: agent
    })
    
    result = executor.run(build_prompt, @scheduled_task.input_context)
    
    # Update execution record
    execution.mark_completed!(result)
    
    {
      content: result[:content],
      canvas_data: result[:canvas_data],
      tools_used: result[:tools_used] || [],
      agents_used: [agent.slug],
      execution_id: execution.id,
      deterministic: true,
      execution_mode: 'agent_only'
    }
  end
  
  # Execute with specific tools ONLY - deterministic mode
  def execute_tool_only
    required_tools = @scheduled_task.required_tools
    
    if required_tools.blank?
      if @scheduled_task.allow_fallback?
        Rails.logger.warn "⚠️ No required tools specified, falling back to Scout"
        return execute_with_scout
      else
        raise "No required tools specified and fallback disabled"
      end
    end
    
    Rails.logger.info "🔧 Executing with tools ONLY: #{required_tools.join(', ')} (deterministic mode)"
    
    user = @scheduled_task.user
    entity = @scheduled_task.entity
    session_id = "scheduled-#{@scheduled_task.id}-#{Time.current.to_i}"
    
    # Execute each required tool in sequence
    tool_results = []
    tools_executed = []
    all_tools_failed = true
    
    required_tools.each do |tool_name|
      catalog = Tools::ToolCatalog.instance
      
      unless catalog.tool_exists?(tool_name)
        if @scheduled_task.allow_fallback?
          Rails.logger.warn "⚠️ Tool '#{tool_name}' not found, skipping"
          tool_results << { tool: tool_name, success: false, error: "Tool not found in catalog" }
          next
        else
          raise "Required tool '#{tool_name}' not found and fallback disabled"
        end
      end
      
      # Build tool arguments from the prompt/context
      tool_args = build_tool_args(tool_name)
      
      begin
        # Use the catalog's execute_tool method which handles instantiation
        result = catalog.execute_tool(
          tool_name,
          tool_args,
          user: user,
          entity: entity,
          context: { session_id: session_id }
        )
        
        success = result[:success] != false
        tool_results << { tool: tool_name, success: success, result: result }
        tools_executed << tool_name
        all_tools_failed = false if success
      rescue => e
        Rails.logger.error "Tool #{tool_name} failed: #{e.message}"
        tool_results << { tool: tool_name, success: false, error: e.message }
        
        unless @scheduled_task.allow_fallback?
          raise "Required tool '#{tool_name}' failed: #{e.message}"
        end
      end
    end
    
    # If ALL tools failed and fallback is enabled, use Scout instead
    if all_tools_failed && @scheduled_task.allow_fallback?
      Rails.logger.warn "⚠️ All #{required_tools.length} tools failed, falling back to Scout"
      Rails.logger.warn "   Failed tools: #{tool_results.map { |r| "#{r[:tool]}: #{r[:error] || 'execution failed'}" }.join(', ')}"
      return execute_with_scout
    end
    
    # Format the results
    content = format_tool_results(tool_results)
    
    {
      content: content,
      canvas_data: nil,
      tools_used: tools_executed,
      tool_results: tool_results,
      session_id: session_id,
      deterministic: true,
      execution_mode: 'tool_only'
    }
  end
  
  # Build arguments for a specific tool based on the task prompt/context
  def build_tool_args(tool_name)
    # Common patterns for tool arguments
    case tool_name
    when 'web_search'
      # Extract search query from prompt
      {
        'query' => extract_search_query,
        'num_results' => @scheduled_task.input_context['num_results'] || 10
      }
    when 'get_data'
      {
        'object_type' => @scheduled_task.input_context['object_type'] || 'Contact',
        'filters' => @scheduled_task.input_context['filters'] || {},
        'options' => @scheduled_task.input_context['options'] || {}
      }
    when 'execute_integration'
      {
        'integration' => @scheduled_task.input_context['integration'],
        'operation' => @scheduled_task.input_context['operation'],
        'params' => @scheduled_task.input_context['params'] || {}
      }
    when 'query_rag_store'
      {
        'query' => @scheduled_task.prompt,
        'top_k' => @scheduled_task.input_context['top_k'] || 5
      }
    when 'create_dynamic_visualization'
      {
        'title' => @scheduled_task.name,
        'data' => @scheduled_task.input_context['visualization_data'] || {},
        'visualization_type' => @scheduled_task.input_context['visualization_type'] || 'report'
      }
    else
      # Return any tool-specific args from input_context
      @scheduled_task.input_context['tool_args'] || {}
    end
  end
  
  def extract_search_query
    # Try to extract a search query from the prompt
    prompt = @scheduled_task.prompt
    
    # Look for explicit query patterns
    if prompt =~ /search for[:\s]+["']?([^"'\n]+)["']?/i
      return $1.strip
    end
    
    if prompt =~ /research[:\s]+["']?([^"'\n]+)["']?/i
      return $1.strip
    end
    
    # Fall back to using the prompt itself (first 100 chars)
    prompt.truncate(100)
  end
  
  def format_tool_results(tool_results)
    output = "# Tool Execution Results\n\n"
    
    tool_results.each do |tr|
      if tr[:success]
        output += "## ✅ #{tr[:tool]}\n"
        output += format_result_content(tr[:result])
      else
        output += "## ❌ #{tr[:tool]}\n"
        output += "Error: #{tr[:error]}\n"
      end
      output += "\n---\n\n"
    end
    
    output
  end
  
  def format_result_content(result)
    case result
    when Hash
      if result[:success] == false
        "Error: #{result[:error] || result[:message]}\n"
      elsif result[:results].is_a?(Array)
        # Search results
        result[:results].map do |r|
          "- **#{r[:title]}**: #{r[:snippet]}\n  #{r[:url]}\n"
        end.join("\n")
      else
        result.to_json
      end
    when Array
      result.map { |r| "- #{r}" }.join("\n")
    else
      result.to_s
    end
  end
  
  def execute_with_agent
    agent = @scheduled_task.agent_plugin
    user = @scheduled_task.user
    entity = @scheduled_task.entity
    
    # Determine if this task requires comprehensive output
    comprehensive = requires_comprehensive_output?
    Rails.logger.info "📋 [ScheduledTask] execute_with_agent - comprehensive_output: #{comprehensive}"
    
    # Create an execution record
    execution = AgentPluginExecution.create!(
      agent_plugin: agent,
      user: user,
      status: 'running',
      input_context: {
        prompt: build_prompt,
        scheduled_task_id: @scheduled_task.id,
        comprehensive_output: comprehensive,
        **@scheduled_task.input_context
      }
    )
    
    # Link the run to the execution
    @run.update!(agent_plugin_execution: execution)
    
    # Execute the agent - pass comprehensive_output flag in context
    executor = Agents::StandardPluginExecutor.new(agent, {
      entity: entity,
      user: user,
      agent_plugin: agent,
      comprehensive_output: comprehensive,  # Pass to executor
      scheduled_task: true  # Indicate this is a scheduled task
    })
    
    result = executor.run(build_prompt, @scheduled_task.input_context.merge(comprehensive_output: comprehensive))
    
    # Update execution record
    execution.mark_completed!(result)
    
    {
      content: result[:content],
      canvas_data: result[:canvas_data],
      tools_used: result[:tools_used] || [],
      execution_id: execution.id
    }
  end
  
  def build_prompt
    base_prompt = @scheduled_task.prompt
    current_time = Time.current
    current_year = current_time.year
    
    # DEBUG: Log task details
    Rails.logger.info "📋 [ScheduledTask] Building prompt for task: #{@scheduled_task.name} (ID: #{@scheduled_task.id})"
    Rails.logger.info "📋 [ScheduledTask] Task type: '#{@scheduled_task.task_type}'"
    Rails.logger.info "📋 [ScheduledTask] requires_comprehensive_output?: #{requires_comprehensive_output?}"
    
    # Add time context with STRONG emphasis on current year
    time_context = <<~CONTEXT
      ⚠️ CRITICAL DATE INFORMATION:
      📅 TODAY'S DATE: #{current_time.strftime('%A, %B %d, %Y')} (YEAR: #{current_year})
      🕐 CURRENT TIME: #{current_time.strftime('%I:%M %p %Z')}
      
      IMPORTANT: When searching for news, events, or current information:
      - We are in the year #{current_year}, NOT #{current_year - 1}
      - Include "#{current_year}" in any web searches for recent news or current events
      - Use time_filter: "week" or "month" for news searches to get recent results
      
      Task type: #{@scheduled_task.task_type}
      This is a scheduled task running automatically.
    CONTEXT
    
    # For research/report tasks, override the default conciseness instructions
    # Scout's system prompt says "be concise" but scheduled reports need to be comprehensive
    if requires_comprehensive_output?
      Rails.logger.info "📋 [ScheduledTask] ✅ ADDING COMPREHENSIVE OUTPUT OVERRIDE"
      time_context += <<~OUTPUT_OVERRIDE

        ═══════════════════════════════════════════════════════════════
        📋 SCHEDULED REPORT TASK - COMPREHENSIVE OUTPUT REQUIRED
        ═══════════════════════════════════════════════════════════════
        
        ⚠️ OVERRIDE YOUR DEFAULT CONCISENESS FOR THIS TASK!
        
        This is an automated SCHEDULED TASK that requires COMPREHENSIVE, DETAILED output.
        The user has specifically requested this report format - follow their instructions exactly.
        
        FOR THIS TASK YOU MUST:
        ✅ Generate DETAILED, COMPREHENSIVE output (not concise summaries)
        ✅ Include ALL sections the user requested in their prompt
        ✅ Provide thorough analysis and explanations
        ✅ Include source links and references where applicable
        ✅ Follow the EXACT format specified in the user's prompt
        ✅ Use multiple web_search calls to gather comprehensive information
        ✅ Don't stop after just one search - be thorough!
        
        ❌ DO NOT:
        - Give brief summaries when detailed content was requested
        - Skip sections the user asked for
        - Say "I'll keep this brief" or similar
        - Truncate or abbreviate the output
        
        The user scheduled this task to receive FULL, DETAILED reports - deliver exactly that.
        ═══════════════════════════════════════════════════════════════
      OUTPUT_OVERRIDE
    end
    
    # Add any custom context
    if @scheduled_task.input_context['additional_context'].present?
      time_context += "\nAdditional context: #{@scheduled_task.input_context['additional_context']}"
    end
    
    "#{time_context}\n\n#{base_prompt}"
  end
  
  # Determine if this task type requires comprehensive output
  # (not the default concise responses Scout normally gives)
  def requires_comprehensive_output?
    # Task types that need detailed, comprehensive output
    comprehensive_types = %w[research_update report_generation]
    
    # Check task type first
    if comprehensive_types.include?(@scheduled_task.task_type)
      Rails.logger.info "📋 [ScheduledTask] Comprehensive output triggered by task_type: #{@scheduled_task.task_type}"
      return true
    end
    
    # Also check prompt for keywords suggesting detailed output is wanted
    prompt_lower = @scheduled_task.prompt.to_s.downcase
    detailed_keywords = [
      'comprehensive', 'detailed', 'full report', 'in-depth',
      'thorough', 'complete analysis', 'executive summary',
      'organized into sections', 'include source links'
    ]
    
    matched_keywords = detailed_keywords.select { |keyword| prompt_lower.include?(keyword) }
    
    if matched_keywords.any?
      Rails.logger.info "📋 [ScheduledTask] Comprehensive output triggered by keywords: #{matched_keywords.join(', ')}"
      return true
    end
    
    Rails.logger.info "📋 [ScheduledTask] ❌ NO comprehensive output trigger found (task_type: #{@scheduled_task.task_type})"
    false
  end
  
  def process_result(result)
    # Generate summary
    summary = generate_summary(result[:content])
    
    # Complete the run
    @run.complete!(
      result_summary: summary,
      result_data: {
        content: result[:content],
        canvas_data: result[:canvas_data],
        tools_used: result[:tools_used],
        session_id: result[:session_id],
        execution_id: result[:execution_id]
      }
    )
    
    # Create work item
    create_work_item(result, summary)
    
    # Handle output delivery
    deliver_output(result, summary)
    
    # Save visualization if one was created
    save_visualization_if_present(result)
    
    Rails.logger.info "✅ Scheduled task completed: #{@scheduled_task.name}"
  end
  
  def generate_summary(content)
    return "Task completed successfully" if content.blank?
    
    # Take first 200 chars as summary
    if content.length > 200
      content[0..197] + "..."
    else
      content
    end
  end
  
  def create_work_item(result, summary)
    AgentWorkItem.create!(
      entity: @scheduled_task.entity,
      user: @scheduled_task.user,
      agent_plugin: @scheduled_task.agent_plugin,
      scheduled_task_run: @run,
      agent_plugin_execution_id: result[:execution_id],
      work_type: 'scheduled_task_completed',
      title: "#{@scheduled_task.task_type_info[:icon]} #{@scheduled_task.name}",
      summary: summary,
      details: result[:content],
      priority: 'normal',
      metadata: {
        task_type: @scheduled_task.task_type,
        tools_used: result[:tools_used],
        has_visualization: result[:canvas_data].present?
      }
    )
  end
  
  def deliver_output(result, summary)
    case @scheduled_task.output_method
    when 'email'
      send_email_result(result, summary)
    when 'notification'
      # Notification is created automatically by ScheduledTaskRun
    when 'both'
      send_email_result(result, summary)
      # Notification is created automatically
    end
  end
  
  def send_email_result(result, summary)
    return unless @scheduled_task.user&.email.present?
    
    Rails.logger.info "📧 Sending task completion email to #{@scheduled_task.user.email}"
    
    ScheduledTaskMailer.task_completed(
      @scheduled_task,
      @run,
      result,
      summary
    ).deliver_later
  rescue => e
    Rails.logger.error "Failed to send task completion email: #{e.message}"
  end
  
  def save_visualization_if_present(result)
    return unless result[:canvas_data].present?
    
    canvas_data = result[:canvas_data]
    return unless canvas_data['html_content'].present? || canvas_data[:html_content].present?
    
    SavedVisualization.create!(
      entity: @scheduled_task.entity,
      user: @scheduled_task.user,
      scheduled_task_run: @run,
      name: "#{@scheduled_task.name} - #{Time.current.strftime('%b %d, %Y')}",
      description: "Auto-generated from scheduled task",
      visualization_type: SavedVisualization.determine_type(canvas_data),
      source_type: 'inline',
      html_content_cache: canvas_data['html_content'] || canvas_data[:html_content],
      canvas_data_cache: canvas_data,
      cache_expires_at: 1.week.from_now,
      original_prompt: @scheduled_task.prompt,
      category: @scheduled_task.task_type,
      metadata: {
        scheduled_task_id: @scheduled_task.id,
        run_id: @run.id,
        auto_generated: true
      }
    )
  end
  
  def create_failure_notification(error)
    UserNotification.create!(
      entity: @scheduled_task.entity,
      user: @scheduled_task.user,
      scheduled_task_run: @run,
      notification_type: 'task_failed',
      title: "❌ #{@scheduled_task.name} failed",
      body: "Error: #{error.message}",
      icon: '❌',
      channel: @scheduled_task.output_method == 'email' ? 'both' : 'in_app',
      priority: 'high',
      action_url: "/scout?view=scheduled_tasks&task_id=#{@scheduled_task.id}",
      action_type: 'view'
    )
    
    # Send failure email if configured
    if @scheduled_task.output_method.in?(%w[email both])
      send_failure_email(error)
    end
  end
  
  def send_failure_email(error)
    return unless @scheduled_task.user&.email.present?
    
    Rails.logger.info "📧 Sending task failure email to #{@scheduled_task.user.email}"
    
    ScheduledTaskMailer.task_failed(
      @scheduled_task,
      @run,
      error.message
    ).deliver_later
  rescue => e
    Rails.logger.error "Failed to send task failure email: #{e.message}"
  end
end

