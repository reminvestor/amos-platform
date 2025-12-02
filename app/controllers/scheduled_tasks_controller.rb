# frozen_string_literal: true

class ScheduledTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_scheduled_task, only: [:show, :edit, :update, :destroy, :pause, :resume, :run_now, :runs, :reset_failures]
  
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

    if @scheduled_task.save
      redirect_to scheduled_task_path(@scheduled_task), notice: 'Scheduled task was successfully created.'
    else
      @available_agents = current_entity.agent_plugins.where(status: 'active')
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @available_agents = current_entity.agent_plugins.where(status: 'active')
  end

  def update
    if @scheduled_task.update(scheduled_task_params)
      redirect_to scheduled_task_path(@scheduled_task), notice: 'Scheduled task was successfully updated.'
    else
      @available_agents = current_entity.agent_plugins.where(status: 'active')
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @scheduled_task.destroy
    redirect_to scheduled_tasks_url, notice: 'Scheduled task was successfully deleted.'
  end

  def pause
    @scheduled_task.pause!
    redirect_to scheduled_task_path(@scheduled_task), notice: 'Scheduled task has been paused.'
  end

  def resume
    @scheduled_task.resume!
    redirect_to scheduled_task_path(@scheduled_task), notice: 'Scheduled task has been resumed.'
  end

  def run_now
    ExecuteScheduledAgentTaskJob.perform_later(@scheduled_task.id)
    redirect_to scheduled_task_path(@scheduled_task), notice: 'Scheduled task has been queued for immediate execution.'
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

  private

  def set_scheduled_task
    @scheduled_task = current_entity.scheduled_agent_tasks
                                    .where(user: current_user)
                                    .find(params[:id])
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

