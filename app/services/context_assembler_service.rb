class ContextAssemblerService
  attr_reader :user, :entity, :task_session
  
  def initialize(user:, entity:, task_session:)
    @user = user
    @entity = entity
    @task_session = task_session
  end
  
  # Assemble minimal context for a step execution
  def assemble_context_for_step(step)
    loadout = step.agent_loadout
    
    context = {
      session_summary: build_session_summary,
      step_context: build_step_context(step),
      available_artifacts: list_available_artifacts(loadout),
      tool_contracts: get_tool_contracts(loadout.tool_allowlist),
      constraints: build_constraints(loadout)
    }
    
    # Build the final prompt
    prompt = build_agent_prompt(loadout, context)
    
    {
      prompt: prompt,
      context: context,
      metadata: {
        token_estimate: estimate_tokens(prompt),
        artifact_count: context[:available_artifacts].length,
        tool_count: loadout.tool_allowlist.length
      }
    }
  end
  
  private
  
  def build_session_summary
    # Get a rolling summary of the session
    recent_events = @task_session.task_events.recent.limit(10)
    
    summary = {
      request: @task_session.metadata['request_text'],
      progress: {
        completed_steps: @task_session.metadata['completed_steps'] || [],
        current_step: @task_session.metadata['current_step'],
        total_steps: @task_session.metadata['total_steps']
      },
      key_results: extract_key_results(recent_events)
    }
    
    # Compress to a brief text summary
    <<~SUMMARY
      Session: #{@task_session.id}
      Request: #{summary[:request]}
      Progress: #{summary[:progress][:completed_steps].length}/#{summary[:progress][:total_steps]} steps complete
      Key Results: #{summary[:key_results].join('; ')}
    SUMMARY
  end
  
  def build_step_context(step)
    # Build context specific to this step
    context = {
      step_id: step.id,
      step_name: step.name,
      description: step.description,
      dependencies: step.dependencies
    }
    
    # Add results from dependent steps
    if step.dependencies.any?
      dependency_results = get_dependency_results(step.dependencies)
      context[:dependency_artifacts] = dependency_results
    end
    
    context
  end
  
  def list_available_artifacts(loadout)
    # Get artifacts this agent can access
    artifacts = Artifact.where(entity: @entity)
    
    # Apply data scope restrictions
    if loadout.data_scopes['read'] && loadout.data_scopes['read'] != ['*']
      allowed_ids = loadout.data_scopes['read'].map(&:to_i)
      artifacts = artifacts.where(id: allowed_ids)
    end
    
    # Return minimal artifact summaries
    artifacts.limit(20).map do |artifact|
      {
        id: artifact.id,
        name: artifact.name,
        source: artifact.source,
        schema: artifact.schema.keys, # Just field names, not full schema
        row_count: artifact.row_count,
        created_at: artifact.created_at
      }
    end
  end
  
  def get_tool_contracts(tool_names)
    # Get minimal tool information
    tool_names.map do |tool_name|
      contract = ToolRegistry.get_contract(tool_name)
      next unless contract
      
      {
        name: tool_name,
        description: contract[:description],
        required_inputs: contract[:input_schema]&.dig('required') || []
      }
    end.compact
  end
  
  def build_constraints(loadout)
    {
      max_tool_calls: loadout.budgets['max_tool_calls'],
      allowed_canvases: loadout.canvas_allowlist,
      requires_confirmation: loadout.confirmations.any?
    }
  end
  
  def build_agent_prompt(loadout, context)
    base_prompt = loadout.generate_prompt(context)
    
    # Add context-specific instructions
    prompt_parts = [base_prompt]
    
    # Add session context
    prompt_parts << "\n## Current Task"
    prompt_parts << context[:session_summary]
    
    # Add step details
    prompt_parts << "\n## Your Assignment"
    prompt_parts << "Step: #{context[:step_context][:step_name]}"
    prompt_parts << "Description: #{context[:step_context][:description]}"
    
    # Add available artifacts
    if context[:available_artifacts].any?
      prompt_parts << "\n## Available Data (Artifacts)"
      context[:available_artifacts].each do |artifact|
        prompt_parts << "- #{artifact[:name]} (ID: #{artifact[:id]}, #{artifact[:row_count]} rows, fields: #{artifact[:schema].join(', ')})"
      end
    end
    
    # Add tool information
    if context[:tool_contracts].any?
      prompt_parts << "\n## Your Tools"
      context[:tool_contracts].each do |tool|
        prompt_parts << "- #{tool[:name]}: #{tool[:description]}"
      end
    end
    
    # Add constraints
    prompt_parts << "\n## Constraints"
    prompt_parts << "- Maximum tool calls: #{context[:constraints][:max_tool_calls]}"
    prompt_parts << "- Allowed canvases: #{context[:constraints][:allowed_canvases].join(', ')}"
    
    # Add artifact-first reminder
    prompt_parts << "\n## Important"
    prompt_parts << "- Reference data by artifact ID, never include raw data in responses"
    prompt_parts << "- Use aggregation tools for analysis, not manual calculations"
    prompt_parts << "- Stream results to allowed canvases for visualization"
    
    prompt_parts.join("\n")
  end
  
  def extract_key_results(events)
    # Extract key results from recent events
    results = []
    
    events.each do |event|
      case event.event_type
      when 'tool_call'
        if event.event_data['success'] && event.event_data['tool']
          results << "#{event.event_data['tool']} executed"
        end
      when 'artifact_created'
        results << "Created artifact: #{event.event_data['name']}"
      when 'step_completed'
        results << "Completed: #{event.event_data['step_name']}"
      end
    end
    
    results.last(5) # Keep it brief
  end
  
  def get_dependency_results(dependency_ids)
    # Get artifact IDs created by dependent steps
    events = TaskEvent.where(
      task_session: @task_session,
      event_type: 'artifact_created'
    ).where("event_data->>'step_id' IN (?)", dependency_ids)
    
    events.map { |e| e.event_data['artifact_id'] }.compact
  end
  
  def estimate_tokens(prompt)
    # Simple token estimation (4 chars ≈ 1 token)
    (prompt.length / 4.0).ceil
  end
end
