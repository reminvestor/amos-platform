# frozen_string_literal: true

class ScheduledTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_scheduled_task, only: [:show, :edit, :update, :destroy, :pause, :resume, :run_now, :runs, :reset_failures]
  skip_before_action :verify_authenticity_token, only: [:api_create, :api_update, :api_destroy]
  
  layout 'customer_admin'

  def index
    @scheduled_tasks = current_entity.scheduled_agent_tasks
                                     .where(user: current_user)
                                     .order(created_at: :desc)
    
    @active_tasks = @scheduled_tasks.active
    @paused_tasks = @scheduled_tasks.paused
    @completed_tasks = @scheduled_tasks.where(status: 'completed')
  end

  def show
    @runs = @scheduled_task.scheduled_task_runs.order(created_at: :desc).limit(20)
  end

  def new
    @scheduled_task = ScheduledAgentTask.new
    @available_agents = current_entity.agent_plugins.where(status: 'active')
  end

  def create
    @scheduled_task = ScheduledAgentTask.new(scheduled_task_params)
    @scheduled_task.entity = current_entity
    @scheduled_task.user = current_user

    respond_to do |format|
      if @scheduled_task.save
        format.html { redirect_to scheduled_task_path(@scheduled_task), notice: 'Scheduled task was successfully created.' }
        format.json { render json: { success: true, task: task_json(@scheduled_task), message: 'Task created successfully' } }
      else
        format.html do
          @available_agents = current_entity.agent_plugins.where(status: 'active')
          render :new, status: :unprocessable_entity
        end
        format.json { render json: { success: false, errors: @scheduled_task.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def edit
    @available_agents = current_entity.agent_plugins.where(status: 'active')
  end

  def update
    respond_to do |format|
      if @scheduled_task.update(scheduled_task_params)
        format.html { redirect_to scheduled_task_path(@scheduled_task), notice: 'Scheduled task was successfully updated.' }
        format.json { render json: { success: true, task: task_json(@scheduled_task), message: 'Task updated successfully' } }
      else
        format.html do
          @available_agents = current_entity.agent_plugins.where(status: 'active')
          render :edit, status: :unprocessable_entity
        end
        format.json { render json: { success: false, errors: @scheduled_task.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    name = @scheduled_task.name
    @scheduled_task.destroy
    
    respond_to do |format|
      format.html { redirect_to scheduled_tasks_url, notice: 'Scheduled task was successfully deleted.' }
      format.json { render json: { success: true, message: "Task '#{name}' deleted" } }
    end
  end

  def pause
    @scheduled_task.pause!
    
    respond_to do |format|
      format.html { redirect_to scheduled_task_path(@scheduled_task), notice: 'Scheduled task has been paused.' }
      format.json { render json: { success: true, message: 'Task paused' } }
    end
  end

  def resume
    @scheduled_task.resume!
    
    respond_to do |format|
      format.html { redirect_to scheduled_task_path(@scheduled_task), notice: 'Scheduled task has been resumed.' }
      format.json { render json: { success: true, message: 'Task resumed' } }
    end
  end

  def run_now
    ExecuteScheduledAgentTaskJob.perform_later(@scheduled_task.id)
    
    respond_to do |format|
      format.html { redirect_to scheduled_task_path(@scheduled_task), notice: 'Scheduled task has been queued for immediate execution.' }
      format.json { render json: { success: true, message: 'Task queued for execution' } }
    end
  end

  def runs
    @runs = @scheduled_task.scheduled_task_runs.order(created_at: :desc)
  end

  def reset_failures
    @scheduled_task.update!(consecutive_failures: 0)
    
    respond_to do |format|
      format.html { redirect_to scheduled_task_path(@scheduled_task), notice: 'Failure counter has been reset. Task can now run again.' }
      format.json { render json: { success: true, message: 'Failure counter reset' } }
    end
  end
  
  # API endpoints for Scout canvas (JSON only)
  def api_create
    @scheduled_task = ScheduledAgentTask.new
    @scheduled_task.entity = current_entity
    @scheduled_task.user = current_user
    
    apply_api_params(@scheduled_task)
    
    if @scheduled_task.save
      render json: { success: true, task: task_json(@scheduled_task), message: 'Task created successfully' }
    else
      render json: { success: false, errors: @scheduled_task.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def api_update
    @scheduled_task = current_entity.scheduled_agent_tasks
                                    .where(user: current_user)
                                    .find(params[:id])
    
    apply_api_params(@scheduled_task)
    
    if @scheduled_task.save
      render json: { success: true, task: task_json(@scheduled_task), message: 'Task updated successfully' }
    else
      render json: { success: false, errors: @scheduled_task.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def api_destroy
    @scheduled_task = current_entity.scheduled_agent_tasks
                                    .where(user: current_user)
                                    .find(params[:id])
    name = @scheduled_task.name
    @scheduled_task.destroy
    render json: { success: true, message: "Task '#{name}' deleted" }
  end

  private

  def set_scheduled_task
    @scheduled_task = current_entity.scheduled_agent_tasks
                                    .where(user: current_user)
                                    .find(params[:id])
  end
  
  def task_json(task)
    {
      id: task.id,
      name: task.name,
      description: task.description,
      task_type: task.task_type,
      prompt: task.prompt,
      schedule_type: task.schedule_type,
      run_at_time: task.run_at_time&.strftime('%H:%M'),
      run_on_day: task.run_on_day,
      timezone: task.timezone,
      enabled: task.enabled?,
      status: task.status,
      execution_mode: task.execution_mode,
      required_tools: task.required_tools,
      required_agent_slug: task.required_agent_slug,
      allow_fallback: task.allow_fallback?,
      output_method: task.output_method,
      max_runs: task.max_runs,
      next_run_at: task.next_run_at&.iso8601,
      run_count: task.run_count,
      consecutive_failures: task.consecutive_failures
    }
  end
  
  # Apply params from API (canvas form) - handles flat JSON structure
  def apply_api_params(task)
    p = params.permit!.to_h
    
    # Basic fields
    task.name = p['name'] if p['name'].present?
    task.description = p['description'] if p.key?('description')
    task.task_type = p['task_type'] if p['task_type'].present?
    task.prompt = p['prompt'] if p['prompt'].present?
    task.schedule_type = p['schedule_type'] if p['schedule_type'].present?
    task.timezone = p['timezone'] if p['timezone'].present?
    task.max_runs = p['max_runs'].presence&.to_i
    
    # Time handling
    if p['run_at_time'].present?
      task.run_at_time = Time.parse(p['run_at_time']) rescue nil
    end
    task.run_on_day = p['run_on_day'].to_i if p['run_on_day'].present?
    
    # Enabled/status
    task.enabled = p['enabled'].to_s == 'true' || p['enabled'] == true || p['enabled'] == 'on'
    
    # Output config
    if p['output_method'].present?
      task.output_config = (task.output_config || {}).merge('method' => p['output_method'])
    end
    
    # Input context (execution mode, tools, etc.)
    input_context = task.input_context || {}
    
    if p['execution_mode'].present?
      input_context['execution_mode'] = p['execution_mode']
    end
    
    if p['required_agent_slug'].present?
      input_context['required_agent_slug'] = p['required_agent_slug']
    elsif p['execution_mode'] != 'agent_only'
      input_context.delete('required_agent_slug')
    end
    
    if p['required_tools'].present?
      tools = p['required_tools']
      tools = tools.split(',').map(&:strip).reject(&:blank?) if tools.is_a?(String)
      input_context['required_tools'] = tools
    elsif p['execution_mode'] != 'tool_only'
      input_context['required_tools'] = []
    end
    
    input_context['allow_fallback'] = p['allow_fallback'].to_s == 'true' || p['allow_fallback'] == true || p['allow_fallback'] == 'on'
    
    task.input_context = input_context
  end

  def scheduled_task_params
    permitted = params.require(:scheduled_agent_task).permit(
      :name, :description, :task_type, :prompt, :schedule_type,
      :cron_expression, :run_at_time, :run_on_day, :timezone,
      :enabled, :max_runs, :expires_at, :agent_plugin_id,
      output_config: [:method]
    )
    
    # Handle input_context separately to allow nested keys
    if params[:scheduled_agent_task][:input_context].present?
      input_context = params[:scheduled_agent_task][:input_context].to_unsafe_h
      
      # Convert required_tools from comma-separated string to array
      if input_context['required_tools'].is_a?(String)
        input_context['required_tools'] = input_context['required_tools']
          .split(',')
          .map(&:strip)
          .reject(&:blank?)
      end
      
      # Merge with existing input_context to preserve other settings
      existing_context = @scheduled_task&.input_context || {}
      permitted[:input_context] = existing_context.merge(input_context)
    end
    
    permitted
  end
end

