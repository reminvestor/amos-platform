class WorkflowEngine
  attr_reader :task_session, :workflow
  
  def initialize(task_session)
    @task_session = task_session
    @workflow = nil
    @progress_callback = nil
    @observability = ObservabilityService.instance
  end
  
  # Create and start a new workflow
  def start_workflow(workflow_spec, initial_inputs = {})
    # Store workflow spec in task session
    @task_session.update_state(workflow_spec: workflow_spec)
    @task_session.add_event('workflow_started', { 
      workflow_type: workflow_spec[:type] || 'generic',
      initial_inputs: initial_inputs 
    })
    
    # Create workflow instance
    @workflow = Workflow.new(workflow_spec)
    
    # Track workflow start
    @observability.track_workflow_event(:workflow_started, @task_session, {
      workflow_type: workflow_spec[:type],
      total_steps: @workflow.steps.length,
      initial_inputs_keys: initial_inputs.keys
    })
    
    # Execute first step
    execute_next_step(initial_inputs)
  end
  
  # Resume an existing workflow
  def resume_workflow(inputs = {})
    workflow_spec = @task_session.workflow_spec
    unless workflow_spec
      return {
        status: 'error',
        message: 'No workflow found in task session'
      }
    end
    
    # Recreate workflow from spec and restore state
    @workflow = Workflow.new(workflow_spec)
    restore_workflow_state
    
    # Execute next step
    execute_next_step(inputs)
  end
  
  # Execute the next step in the workflow
  def execute_next_step(inputs = {})
    unless @workflow
      return {
        status: 'error',
        message: 'No active workflow'
      }
    end
    
    # Log step execution
    current_step = @workflow.current_step
    if current_step
      @task_session.add_event('step_started', {
        step_id: current_step.id,
        step_type: current_step.type,
        inputs: sanitize_inputs(inputs)
      })
    end
    
    # For user_input steps, check if we have actual form data or just initial workflow inputs
    if current_step && ['user_input', 'form_input'].include?(current_step.type)
      # Get the fields expected by this step
      expected_fields = current_step.config[:fields]&.map { |f| f[:name].to_s } || []
      
      # Check if inputs contain any of the expected fields
      has_form_data = inputs.keys.any? { |key| expected_fields.include?(key.to_s) }
      
      if has_form_data
        # We have form data, resolve and pass it through
        resolved_inputs = resolve_variable_substitutions(inputs)
      else
        # No form data yet, pass empty inputs to get the form
        resolved_inputs = {}
      end
    else
      # For other step types, resolve variables normally
      resolved_inputs = resolve_variable_substitutions(inputs)
    end
    
    # Execute the step
    result = @workflow.execute_next_step(resolved_inputs)
    
    # Log result and update state
    handle_step_result(result)
    
    # Trigger progress callback if set
    trigger_progress_callback(result)
    
    result
  end
  
  # Skip the current step
  def skip_current_step(reason = 'Skipped by user')
    unless @workflow
      return {
        status: 'error',
        message: 'No active workflow'
      }
    end
    
    current_step = @workflow.current_step
    if current_step
      @task_session.add_event('step_skipped', {
        step_id: current_step.id,
        reason: reason
      })
    end
    
    @workflow.skip_current_step(reason)
    update_workflow_state
    
    {
      status: 'step_skipped',
      message: "Step skipped: #{reason}",
      next_step: @workflow.current_step&.to_hash
    }
  end
  
  # Get workflow progress
  def progress
    return { status: 'no_workflow' } unless @workflow
    
    @workflow.progress.merge(
      task_session_id: @task_session.id,
      workflow_type: @task_session.workflow_spec&.dig(:type) || 'unknown'
    )
  end
  
  # Set progress callback for real-time updates
  def on_progress(&block)
    @progress_callback = block
  end
  
  # Get workflow execution history
  def execution_history
    return [] unless @workflow
    
    @workflow.execution_history
  end
  
  # Create common workflow types
  def self.create_landing_page_workflow(user_inputs = {})
    {
      type: 'landing_page_creation',
      description: 'Create a landing page with user input',
      steps: [
        {
          id: 'collect_business_info',
          type: 'user_input',
          config: {
            title: 'Business Information',
            description: 'Tell us about your business',
            fields: [
              { name: 'business_name', type: 'text', required: true, label: 'Business Name' },
              { name: 'industry', type: 'select', required: true, label: 'Industry',
                options: ['Consulting', 'Technology', 'Healthcare', 'Finance', 'Retail', 'Other'] },
              { name: 'target_audience', type: 'textarea', required: true, label: 'Target Audience' }
            ]
          }
        },
        {
          id: 'collect_design_preferences',
          type: 'user_input',
          config: {
            title: 'Design Preferences',
            description: 'Choose your design style',
            fields: [
              { name: 'theme', type: 'select', required: true, label: 'Theme',
                options: ['clean', 'modern', 'bold', 'professional', 'creative'] },
              { name: 'primary_color', type: 'color', label: 'Primary Color (optional)' },
              { name: 'style_notes', type: 'textarea', label: 'Additional Style Notes' }
            ]
          }
        },
        {
          id: 'generate_landing_page',
          type: 'tool_call',
          config: {
            tool: 'generate_landing_page_dsl',
            description: 'Generate landing page from your inputs',
            inputs: {
              business_info: '${collect_business_info.data}',
              design_preferences: '${collect_design_preferences.data}'
            }
          }
        },
        {
          id: 'compile_html',
          type: 'tool_call',
          config: {
            tool: 'compile_landing_page_html',
            description: 'Compile DSL to HTML',
            inputs: {
              dsl: '${generate_landing_page.data.dsl}',
              slug: '${collect_business_info.data.business_name}'
            }
          }
        }
      ]
    }
  end
  
  def self.create_contact_import_workflow
    {
      type: 'contact_import',
      description: 'Import contacts from various sources',
      steps: [
        {
          id: 'select_import_source',
          type: 'user_input',
          config: {
            title: 'Import Source',
            description: 'Choose how you want to import contacts',
            fields: [
              { name: 'source', type: 'select', required: true, label: 'Import Method',
                options: ['CSV Upload', 'Manual Entry', 'API Integration'] }
            ]
          }
        },
        {
          id: 'upload_data',
          type: 'conditional',
          config: {
            condition: 'source equals CSV Upload',
            true_step: 'process_csv',
            false_step: 'manual_entry'
          }
        },
        {
          id: 'process_csv',
          type: 'tool_call',
          config: {
            tool: 'process_csv_contacts',
            description: 'Process uploaded CSV file'
          }
        },
        {
          id: 'validate_contacts',
          type: 'validation',
          config: {
            description: 'Validate contact data',
            rules: [
              { field: 'email', type: 'required' },
              { field: 'email', type: 'email' },
              { field: 'first_name', type: 'required' }
            ]
          }
        },
        {
          id: 'import_contacts',
          type: 'tool_call',
          config: {
            tool: 'import_contacts',
            description: 'Import validated contacts'
          }
        }
      ]
    }
  end
  
  def self.create_campaign_workflow
    {
      type: 'campaign_creation',
      description: 'Create and configure a marketing campaign',
      steps: [
        {
          id: 'campaign_details',
          type: 'user_input',
          config: {
            title: 'Campaign Details',
            description: 'Basic campaign information',
            fields: [
              { name: 'campaign_name', type: 'text', required: true, label: 'Campaign Name' },
              { name: 'campaign_type', type: 'select', required: true, label: 'Campaign Type',
                options: ['Email', 'Social Media', 'Mixed'] },
              { name: 'description', type: 'textarea', label: 'Campaign Description' }
            ]
          }
        },
        {
          id: 'select_contacts',
          type: 'tool_call',
          config: {
            tool: 'get_contact_groups',
            description: 'Load available contact groups'
          }
        },
        {
          id: 'choose_template',
          type: 'user_input',
          config: {
            title: 'Email Template',
            description: 'Choose or create an email template',
            fields: [
              { name: 'template_choice', type: 'select', required: true, label: 'Template Option',
                options: ['Use Existing', 'Create New'] },
              { name: 'template_id', type: 'select', label: 'Existing Template' }
            ]
          }
        },
        {
          id: 'create_campaign',
          type: 'tool_call',
          config: {
            tool: 'create_campaign',
            description: 'Create the campaign'
          }
        }
      ]
    }
  end
  
  private
  
  def handle_step_result(result)
    case result[:status]
    when 'step_completed'
      @task_session.add_event('step_completed', {
        step_id: result[:result][:step_id] || @workflow.current_step&.id,
        result: sanitize_result(result[:result])
      })
      
    when 'completed'
      @task_session.add_event('workflow_completed', {
        completed_steps: result[:completed_steps],
        final_result: sanitize_result(result[:result])
      })
      @task_session.update!(status: 'completed')
      
      # Track workflow completion
      @observability.track_workflow_event(:workflow_completed, @task_session, {
        total_steps: @workflow.steps.length,
        completion_time_seconds: Time.current - @task_session.created_at
      })
      
    when 'failed'
      @task_session.add_event('workflow_failed', {
        failed_step: result[:failed_step],
        error: result[:error]
      })
      @task_session.update!(status: 'failed')
      
      # Track workflow failure
      @observability.track_workflow_event(:workflow_failed, @task_session, {
        failed_step: result[:failed_step],
        error: result[:error],
        steps_completed: @workflow.steps.count { |s| s.status == 'completed' }
      })
      
    when 'awaiting_input'
      @task_session.add_event('step_awaiting_input', {
        step_id: result[:step][:id],
        form: result[:form]
      })
    end
    
    # Always update workflow state
    update_workflow_state
  end
  
  def update_workflow_state
    return unless @workflow
    
    @task_session.update_state(
      current_step: @workflow.current_step&.id,
      workflow_status: @workflow.status,
      workflow_progress: @workflow.progress
    )
  end
  
  def restore_workflow_state
    return unless @workflow && @task_session.current_step
    
    # Find and mark completed steps based on task session state
    completed_steps = @task_session.task_events
                                  .by_type('step_completed')
                                  .pluck('payload -> step_id')
    
    @workflow.steps.each do |step|
      if completed_steps.include?(step.id)
        step.mark_completed({ status: 'success', message: 'Restored from session' })
      end
    end
    
    # Set current step
    if @task_session.current_step
      @workflow.instance_variable_set(:@current_step, 
        @workflow.find_step(@task_session.current_step)
      )
    end
  end
  
  def trigger_progress_callback(result)
    return unless @progress_callback
    
    begin
      @progress_callback.call(progress, result)
    rescue => e
      Rails.logger.error "Workflow progress callback failed: #{e.message}"
    end
  end
  
  def sanitize_inputs(inputs)
    # Remove sensitive data from inputs before logging
    inputs.except(:password, :api_key, :secret, :token)
  end
  
  def resolve_variable_substitutions(inputs)
    return inputs unless inputs.is_a?(Hash)
    
    resolved = inputs.deep_dup
    execution_history = @workflow&.execution_history || []
    
    resolved.each do |key, value|
      if value.is_a?(String) && value.start_with?('${') && value.end_with?('}')
        # Extract variable path: ${step_id.data.field}
        variable_path = value[2..-2] # Remove ${ and }
        resolved_value = resolve_variable_path(variable_path, execution_history)
        resolved[key] = resolved_value if resolved_value
      elsif value.is_a?(Hash)
        resolved[key] = resolve_variable_substitutions(value)
      end
    end
    
    resolved
  end
  
  def resolve_variable_path(path, execution_history)
    # Parse path like "step_id.data.field"
    parts = path.split('.')
    return nil if parts.empty?
    
    step_id = parts.first
    
    # Find the step result
    step_result = execution_history.find { |step| step[:id] == step_id }
    return nil unless step_result && step_result[:result]
    
    # Navigate through the path
    current_value = step_result[:result]
    parts[1..-1].each do |part|
      if current_value.is_a?(Hash)
        current_value = current_value[part] || current_value[part.to_sym]
      else
        return nil
      end
    end
    
    current_value
  end

  def sanitize_result(result)
    return result unless result.is_a?(Hash)
    
    # Remove sensitive data from results before logging
    result.except(:password, :api_key, :secret, :token)
  end
end
