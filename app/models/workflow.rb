class Workflow
  attr_reader :steps, :current_step, :spec, :status
  
  # Workflow statuses
  STATUSES = %w[pending in_progress completed failed cancelled].freeze
  
  def initialize(spec)
    @spec = spec.with_indifferent_access
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
      case result[:status]
      when 'success', 'completed'
        @completed_steps << step.id
        step.mark_completed(result)
        
        # Move to next step
        @current_step = find_next_step
        
        # Check if workflow is complete
        if @current_step.nil?
          @status = 'completed'
          return {
            status: 'completed',
            message: 'Workflow completed successfully',
            result: result,
            completed_steps: @completed_steps
          }
        else
          return {
            status: 'step_completed',
            message: "Step '#{step.id}' completed",
            result: result,
            next_step: @current_step.to_hash
          }
        end
        
      when 'failed', 'error'
        @failed_steps << step.id
        step.mark_failed(result[:error] || 'Unknown error')
        @status = 'failed'
        
        return {
          status: 'failed',
          message: "Step '#{step.id}' failed: #{result[:error]}",
          failed_step: step.id,
          error: result[:error]
        }
        
      when 'awaiting_input'
        return {
          status: 'awaiting_input',
          step: step.to_hash,
          message: "Step '#{step.id}' is awaiting user input",
          form: result[:form]
        }
        
      else
        return {
          status: 'in_progress',
          message: "Step '#{step.id}' is processing",
          result: result
        }
      end
      
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
      
      Step.new(step_spec)
    end
  end
  
  def find_next_step
    @steps.find { |step| step.status == 'pending' }
  end
end
