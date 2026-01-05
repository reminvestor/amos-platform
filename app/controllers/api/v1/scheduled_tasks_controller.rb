# frozen_string_literal: true

module Api
  module V1
    class ScheduledTasksController < BaseController
      before_action :set_task, only: [:show, :update, :destroy, :pause, :resume, :run_now]

      def index
        @tasks = ScheduledAgentTask.where(user: current_user, entity: current_entity)
                                   .order(created_at: :desc)
                                   .page(params[:page] || 1)
                                   .per(params[:per_page] || 20)

        # Apply status filter
        case params[:status]
        when 'active'
          @tasks = @tasks.where(status: 'active', enabled: true)
        when 'paused'
          @tasks = @tasks.where(status: 'paused')
        when 'completed'
          @tasks = @tasks.where(status: 'completed')
        when 'failed'
          @tasks = @tasks.where(status: 'failed')
        when 'archived'
          @tasks = @tasks.where(status: 'archived')
        end

        if params[:task_type].present?
          @tasks = @tasks.where(task_type: params[:task_type])
        end

        render json: {
          data: @tasks.map { |t| scheduled_task_json(t) },
          pagination: {
            current_page: @tasks.current_page,
            total_pages: @tasks.total_pages,
            total_count: @tasks.total_count,
            per_page: @tasks.limit_value
          },
          counts: {
            active: ScheduledAgentTask.where(user: current_user, entity: current_entity).where(status: 'active', enabled: true).count,
            paused: ScheduledAgentTask.where(user: current_user, entity: current_entity).where(status: 'paused').count,
            completed: ScheduledAgentTask.where(user: current_user, entity: current_entity).where(status: 'completed').count,
            failed: ScheduledAgentTask.where(user: current_user, entity: current_entity).where(status: 'failed').count,
            total: ScheduledAgentTask.where(user: current_user, entity: current_entity).where.not(status: 'archived').count
          }
        }
      end

      def show
        render json: scheduled_task_detail_json(@task)
      end

      def create
        @task = ScheduledAgentTask.new(task_params)
        @task.user = current_user
        @task.entity = current_entity

        if @task.save
          render json: scheduled_task_json(@task), status: :created
        else
          render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @task.update(task_params)
          render json: scheduled_task_json(@task)
        else
          render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @task.archive!
        head :no_content
      end

      def pause
        @task.pause!
        render json: scheduled_task_json(@task)
      end

      def resume
        @task.resume!
        render json: scheduled_task_json(@task)
      end

      def run_now
        unless @task.can_run?
          render json: { message: "Task cannot be run at this time" }, status: :unprocessable_entity
          return
        end

        # Queue the task for immediate execution
        ExecuteScheduledAgentTaskJob.perform_later(@task.id)

        render json: {
          message: "Task queued for execution",
          task: scheduled_task_json(@task)
        }
      end

      def task_types
        render json: {
          data: ScheduledAgentTask::TASK_TYPES.map do |key, value|
            {
              id: key,
              name: value[:name],
              description: value[:description],
              icon: value[:icon]
            }
          end
        }
      end

      private

      def set_task
        @task = ScheduledAgentTask.where(user: current_user, entity: current_entity).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { message: "Scheduled task not found" }, status: :not_found
      end

      def task_params
        params.permit(:name, :description, :task_type, :prompt, :schedule_type,
                     :cron_expression, :run_at_time, :run_on_day, :timezone,
                     :max_runs, :expires_at, :enabled)
      end

      def scheduled_task_json(task)
        {
          id: task.id,
          name: task.name,
          description: task.description,
          task_type: task.task_type,
          task_type_info: task.task_type_info,
          schedule_type: task.schedule_type,
          status: task.status,
          enabled: task.enabled,
          next_run_at: task.next_run_at,
          last_run_at: task.last_run_at,
          run_count: task.run_count,
          failure_count: task.failure_count,
          consecutive_failures: task.consecutive_failures,
          can_run: task.can_run?,
          created_at: task.created_at,
          updated_at: task.updated_at
        }
      end

      def scheduled_task_detail_json(task)
        scheduled_task_json(task).merge(
          prompt: task.prompt,
          cron_expression: task.cron_expression,
          run_at_time: task.run_at_time,
          run_on_day: task.run_on_day,
          timezone: task.timezone,
          max_runs: task.max_runs,
          expires_at: task.expires_at,
          input_context: task.input_context,
          output_config: task.output_config,
          execution_mode: task.execution_mode,
          agent_name: task.agent_plugin&.name
        )
      end
    end
  end
end
