# frozen_string_literal: true

module Admin
  class ScheduledTasksController < Admin::BaseController
    before_action :set_scheduled_task, only: [:show, :edit, :update, :destroy, :pause, :resume, :run_now]

    def index
      @scheduled_tasks = ScheduledAgentTask
        .includes(:user, :entity, :agent_plugin)
        .order(created_at: :desc)
      
      # Filter by status
      if params[:status].present?
        @scheduled_tasks = @scheduled_tasks.where(status: params[:status])
      end
      
      # Filter by task type
      if params[:task_type].present?
        @scheduled_tasks = @scheduled_tasks.by_type(params[:task_type])
      end
      
      @scheduled_tasks = @scheduled_tasks.page(params[:page]).per(25)
      
      # Stats
      @stats = {
        total: ScheduledAgentTask.count,
        active: ScheduledAgentTask.active.count,
        paused: ScheduledAgentTask.paused.count,
        due_now: ScheduledAgentTask.due_now.count,
        runs_today: ScheduledTaskRun.today.count,
        success_rate: calculate_success_rate
      }
    end

    def show
      @recent_runs = @scheduled_task.scheduled_task_runs
        .includes(:agent_plugin_execution)
        .order(created_at: :desc)
        .limit(20)
      
      @run_stats = {
        total_runs: @scheduled_task.run_count,
        failures: @scheduled_task.failure_count,
        success_rate: @scheduled_task.run_count > 0 ? 
          ((@scheduled_task.run_count - @scheduled_task.failure_count).to_f / @scheduled_task.run_count * 100).round(1) : 0,
        avg_duration: @scheduled_task.scheduled_task_runs.completed.average(:duration_ms)&.round || 0
      }
    end

    def new
      @scheduled_task = ScheduledAgentTask.new
      @agents = AgentPlugin.where(status: 'active').order(:name)
      @entities = Entity.order(:name)
    end

    def create
      @scheduled_task = ScheduledAgentTask.new(scheduled_task_params)
      
      if @scheduled_task.save
        redirect_to admin_scheduled_task_path(@scheduled_task), 
          notice: "Scheduled task '#{@scheduled_task.name}' created successfully."
      else
        @agents = AgentPlugin.where(status: 'active').order(:name)
        @entities = Entity.order(:name)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @agents = AgentPlugin.where(status: 'active').order(:name)
      @entities = Entity.order(:name)
    end

    def update
      if @scheduled_task.update(scheduled_task_params)
        redirect_to admin_scheduled_task_path(@scheduled_task), 
          notice: "Scheduled task updated successfully."
      else
        @agents = AgentPlugin.where(status: 'active').order(:name)
        @entities = Entity.order(:name)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      name = @scheduled_task.name
      @scheduled_task.destroy
      redirect_to admin_scheduled_tasks_path, notice: "Scheduled task '#{name}' deleted."
    end

    def pause
      @scheduled_task.pause!
      redirect_to admin_scheduled_task_path(@scheduled_task), 
        notice: "Task paused successfully."
    end

    def resume
      @scheduled_task.resume!
      redirect_to admin_scheduled_task_path(@scheduled_task), 
        notice: "Task resumed successfully."
    end

    def run_now
      if @scheduled_task.can_run?
        ExecuteScheduledAgentTaskJob.perform_later(@scheduled_task.id)
        redirect_to admin_scheduled_task_path(@scheduled_task), 
          notice: "Task execution queued. Check back shortly for results."
      else
        redirect_to admin_scheduled_task_path(@scheduled_task), 
          alert: "Task cannot be run. Check status and configuration."
      end
    end

    def runs
      @runs = ScheduledTaskRun
        .includes(:scheduled_agent_task, :user, :agent_plugin_execution)
        .order(created_at: :desc)
      
      if params[:status].present?
        @runs = @runs.where(status: params[:status])
      end
      
      if params[:task_id].present?
        @runs = @runs.where(scheduled_agent_task_id: params[:task_id])
      end
      
      @runs = @runs.page(params[:page]).per(50)
    end

    private

    def set_scheduled_task
      @scheduled_task = ScheduledAgentTask.find(params[:id])
    end

    def scheduled_task_params
      params.require(:scheduled_agent_task).permit(
        :entity_id, :user_id, :agent_plugin_id, :name, :description,
        :task_type, :prompt, :schedule_type, :cron_expression,
        :run_at_time, :run_on_day, :timezone, :enabled, :max_runs, :expires_at,
        input_context: {}, output_config: {}
      )
    end

    def calculate_success_rate
      total = ScheduledTaskRun.where('created_at >= ?', 30.days.ago).count
      return 0 if total.zero?
      
      successful = ScheduledTaskRun.completed.where('created_at >= ?', 30.days.ago).count
      ((successful.to_f / total) * 100).round(1)
    end
  end
end

