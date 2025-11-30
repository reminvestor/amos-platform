# frozen_string_literal: true

class ScheduledTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_scheduled_task, only: [:show, :edit, :update, :destroy, :pause, :resume, :run_now, :runs]
  
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

  private

  def set_scheduled_task
    @scheduled_task = current_entity.scheduled_agent_tasks
                                    .where(user: current_user)
                                    .find(params[:id])
  end

  def scheduled_task_params
    params.require(:scheduled_agent_task).permit(
      :name, :description, :task_type, :prompt, :schedule_type,
      :cron_expression, :run_at_time, :run_on_day, :timezone,
      :enabled, :max_runs, :expires_at, :agent_plugin_id,
      input_context: {}, output_config: {}
    )
  end
end

