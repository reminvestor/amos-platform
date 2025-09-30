class Workflow
  attr_reader :steps, :current_step, :spec, :status, :name
  
  # Workflow statuses
  STATUSES = %w[pending in_progress completed failed cancelled].freeze
  
  def initialize(spec, execution_context = {})
    @spec = spec.with_indifferent_access
    @name = @spec[:name] || @spec[:type] || 'Workflow'
    @execution_context = execution_context
    # Add workflow reference to execution context so steps can access it
    @execution_context[:workflow] = self
    @steps = build_steps(@spec[:steps] || [])
    @current_step = find_next_step
    @status = 'pending'
    @completed_steps = []
    @failed_steps = []
  end
  
  # Execute the next step in the workflow
  def execute_next_step(inputs = {})
    return { status: 'completed', message: 'Workflow already completed' } if completed?
    return { status: 'failed', message: 'Workflow has failed' } if failed?
    
    unless @current_step
      @status = 'completed'
      return { status: 'completed', message: 'No more steps to execute' }
    end
    
    step = @current_step
    @status = 'in_progress'
    
    begin
      # Check if we need user input
      if step.requires_input? && inputs.empty?
        return { 
          status: 'awaiting_input', 
          step: step.to_hash,
          message: "Step '#{step.id}' requires user input"
        }
      end
      
      # Execute the step
      result = step.execute(inputs)
      
      # Handle step result
      # Check both status and success fields for compatibility
      # Need to check nested result structure: result.result.result.success
      # If any level explicitly says success: false, it's a failure
      has_explicit_failure = result.dig(:result, :success) == false ||
                            result.dig(:result, :result, :success) == false ||
                            result.dig(:data, :result, :success) == false
      
      is_successful = !has_explicit_failure && (
                      result[:status] == 'success' || 
                      result[:status] == 'completed' || 
                      result[:status] == 'step_completed' ||
                      (result[:result] && result[:result][:success] == true) ||
                      (result.dig(:result, :result, :success) == true)
                    )
      
      if is_successful
        @completed_steps << step.id
        step.mark_completed(result)
        
        # Always return step_completed first, even for the last step
        step_result = {
          status: 'step_completed',
          message: "Step '#{step.id}' completed",
          result: result,
          step_id: step.id,
          executing_step_id: step.id
        }
        
        # Move to next step
        @current_step = find_next_step
        
        # Add workflow completion info if this was the last step
        if @current_step.nil?
          @status = 'completed'
          step_result[:workflow_complete] = true
          step_result[:completed_steps] = @completed_steps
        else
          step_result[:next_step] = @current_step.to_hash
        end
        
        return step_result
      else
        # Step failed (when is_successful is false)
        error_message = result[:error] || 
                       result.dig(:result, :error) || 
                       result.dig(:result, :result, :error) || 
                       'Unknown error'
                       
        @failed_steps << step.id
        step.mark_failed(error_message)
        @status = 'failed'
        
        return {
          status: 'failed',
          message: "Step '#{step.id}' failed: #{error_message}",
          failed_step: step.id,
          error: error_message
        }
      end
      
      # Handle awaiting_input separately if needed
      if result[:status] == 'awaiting_input'
        return {
          status: 'awaiting_input',
          step: step.to_hash,
          message: "Step '#{step.id}' is awaiting user input",
          form: result[:form]
        }
      end
      
      # Default case - shouldn't normally reach here
      return {
        status: 'in_progress',
        message: "Step '#{step.id}' is processing",
        result: result
      }
      
    rescue => e
      @failed_steps << step.id
      step.mark_failed(e.message)
      @status = 'failed'
      
      {
        status: 'failed',
        message: "Step '#{step.id}' failed with exception: #{e.message}",
        failed_step: step.id,
        error: e.message
      }
    end
  end
  
  # Skip the current step
  def skip_current_step(reason = 'Skipped by user')
    return false unless @current_step
    
    @current_step.mark_skipped(reason)
    @current_step = find_next_step
    true
  end
  
  # Get workflow progress
  def progress
    total_steps = @steps.length
    completed_count = @completed_steps.length
    
    {
      total_steps: total_steps,
      completed_steps: completed_count,
      remaining_steps: total_steps - completed_count,
      progress_percentage: total_steps > 0 ? (completed_count.to_f / total_steps * 100).round(1) : 0,
      current_step: @current_step&.to_hash,
      status: @status
    }
  end
  
  # Check if workflow is completed
  def completed?
    @status == 'completed' || (@current_step.nil? && @steps.any?)
  end
  
  # Check if workflow has failed
  def failed?
    @status == 'failed'
  end
  
  # Get completed steps with their results
  def completed_steps_data
    @steps.select { |s| s.status == 'completed' }.map(&:to_hash)
  end
  
  # Get all steps as hash
  def to_hash
    {
      spec: @spec,
      status: @status,
      progress: progress,
      steps: @steps.map(&:to_hash),
      completed_steps: @completed_steps,
      failed_steps: @failed_steps
    }
  end
  
  # Alias for compatibility
  alias_method :to_h, :to_hash
  
  # Find a step by ID
  def find_step(step_id)
    @steps.find { |step| step.id == step_id }
  end
  
  # Get step execution history
  def execution_history
    @steps.map do |step|
      {
        id: step.id,
        type: step.type,
        status: step.status,
        started_at: step.started_at,
        completed_at: step.completed_at,
        error: step.error,
        result: step.result
      }
    end
  end
  
  private
  
  def build_steps(step_specs)
    step_specs.map.with_index do |step_spec, index|
      # Ensure step has an ID
      step_spec = step_spec.with_indifferent_access
      step_spec[:id] ||= "step_#{index + 1}"
      
      step = Step.new(step_spec)
      step.instance_variable_set(:@execution_context, @execution_context)
      step
    end
  end
  
  def find_next_step
    # Find the next step that:
    # 1. Is pending
    # 2. Has all its dependencies completed
    @steps.find do |step|
      step.status == 'pending' && step.dependencies_met?(@completed_steps)
    end
  end
end
