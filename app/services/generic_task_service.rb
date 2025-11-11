class GenericTaskService
  def initialize(task_session)
    @task = task_session
    @user = task_session.user
    @entity = @user.entity
    @progress_callback = nil
  end
  
  def execute_with_progress(&block)
    @progress_callback = block
    
    # Report initial progress
    report_progress(10, "Initializing task execution")
    
    begin
      # Get model preference or use default
      model = @task.model_preference || 'claude-sonnet-4-5'
      
      # Create appropriate agent loadout
      agent_loadout = AgentLoadout.new(
        agent_role: determine_agent_role
      )
      
      # Initialize Scout service with task context
      scout_service = ScoutGenericToolsServiceV2.new(
        @user,
        @entity,
        @task.parent_conversation_id || SecureRandom.uuid,
        agent_loadout: agent_loadout,
        model: model
      )
      
      report_progress(20, "Loading context and tools")
      
      # Set task context including any dependencies' results
      context = build_execution_context
      scout_service.set_context(
        task_session: @task,
        task_metadata: @task.metadata,
        dependency_results: context[:dependency_results],
        execution_mode: 'parallel_task'
      )
      
      report_progress(30, "Executing task")
      
      # Build the prompt from task description
      prompt = build_task_prompt(context)
      
      # Execute with streaming to capture progress
      final_response = nil
      
      result = scout_service.process_message_with_tools_streaming(
        prompt,
        lambda do |progress_data|
          # Handle both string and hash formats
          if progress_data.is_a?(String)
            # Simple string message
            report_progress(50, progress_data)
          elsif progress_data.is_a?(Hash)
            # Structured progress data
            case progress_data[:type]
            when "content_chunk"
              # Accumulate content chunks
              final_response ||= ""
              final_response += progress_data[:content] if progress_data[:content]
              report_progress(50, "Processing response...")
            when "tool_start"
              report_progress(70, "Using tool: #{progress_data[:tool_name] || progress_data[:name]}")
            when "tool_complete"
              report_progress(80, "Tool completed")
            when "phase_progress"
              report_progress(60, progress_data[:message])
            when "error"
              raise "Task execution error: #{progress_data[:message]}"
            else
              # Log other events
              Rails.logger.debug "GenericTaskService received progress: #{progress_data.inspect}"
            end
          end
        end,
        [], # Empty conversation history
        nil  # No current canvas
      )
      
      report_progress(95, "Saving results")
      
      # Extract the actual message from the result
      if result && result[:final_response] && result[:final_response][:message]
        final_response = result[:final_response][:message]
      end
      
      # Process and structure the result
      processed_result = process_result(final_response)
      
      # Store result in task session
      @task.add_event('execution_completed', {
        result: processed_result,
        model_used: model,
        execution_time_ms: (Time.current - @task.started_at) * 1000
      })
      
      report_progress(100, "Task completed successfully")
      
      processed_result
    rescue => e
      report_progress(100, "Task failed: #{e.message}")
      raise
    end
  end
  
  private
  
  def determine_agent_role
    case @task.task_type
    when 'analysis'
      'data_analyst'
    when 'campaign'
      'campaign_manager'
    when 'voice_followup'
      'voice_assistant'
    else
      'main_chat'
    end
  end
  
  def build_execution_context
    context = {
      task_description: @task.metadata['description'],
      required_tools: @task.metadata['required_tools'] || [],
      dependency_results: {}
    }
    
    # Gather results from dependencies
    @task.task_dependencies.includes(:depends_on_task).each do |dep|
      dep_task = dep.depends_on_task
      if dep_task.status == 'completed' && dep_task.state['result']
        context[:dependency_results][dep_task.id] = dep_task.state['result']
      end
    end
    
    context
  end
  
  def build_task_prompt(context)
    prompt = context[:task_description]
    
    # Add dependency context if available
    if context[:dependency_results].any?
      prompt += "\n\nContext from previous tasks:\n"
      context[:dependency_results].each do |task_id, result|
        prompt += "- Task #{task_id}: #{result[:summary] || result[:response]}\n"
      end
    end
    
    # Add specific instructions for parallel execution
    prompt += "\n\nNote: You are executing a specific subtask as part of a larger request. "
    prompt += "Focus only on: #{context[:task_description]}"
    
    prompt
  end
  
  def process_result(response)
    # Structure the result based on task type
    result = {
      response: response,
      timestamp: Time.current,
      task_type: @task.task_type
    }
    
    # Extract structured data for specific task types
    case @task.task_type
    when 'analysis'
      result[:data] = extract_analysis_data(response)
    when 'campaign'
      result[:campaign_data] = extract_campaign_data(response)
    end
    
    # Add summary for dependent tasks
    result[:summary] = generate_summary(response)
    
    result
  end
  
  def extract_analysis_data(response)
    # Use simple regex or keyword extraction for now
    # In production, might use structured output from LLM
    {
      metrics: response.scan(/(\d+(?:\.\d+)?%?)/).flatten,
      entities: response.scan(/(?:campaign|email|landing page|contact)s?/i).uniq
    }
  end
  
  def extract_campaign_data(response)
    {
      mentioned_campaigns: response.scan(/campaign[s]?\s+(?:named\s+)?["']([^"']+)["']/i).flatten
    }
  end
  
  def generate_summary(response)
    # Take first paragraph or first 200 characters
    response.split("\n\n").first || response[0..200]
  end
  
  def report_progress(percentage, message = nil)
    @progress_callback&.call(percentage, message)
  end
end
