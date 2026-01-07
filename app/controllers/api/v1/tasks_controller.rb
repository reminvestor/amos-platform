# frozen_string_literal: true

module Api
  module V1
    class TasksController < BaseController
      before_action :set_task, only: [:show, :update, :destroy]

      def index
        # Tasks are stored in task_sessions for this app
        @tasks = TaskSession.where(user: current_user)
                            .order(created_at: :desc)
                            .page(params[:page] || 1)
                            .per(params[:per_page] || 20)

        if params[:status].present?
          @tasks = @tasks.where(status: params[:status])
        end

        render json: {
          data: @tasks.map { |t| task_json(t) },
          pagination: {
            current_page: @tasks.current_page,
            total_pages: @tasks.total_pages,
            total_count: @tasks.total_count,
            per_page: @tasks.limit_value
          }
        }
      end

      def show
        render json: task_detail_json(@task)
      end

      def create
        @task = TaskSession.new(task_params)
        @task.user = current_user
        # Note: TaskSession inherits entity from user association

        if @task.save
          render json: task_json(@task), status: :created
        else
          render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @task.update(task_params)
          render json: task_json(@task)
        else
          render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @task.destroy
        head :no_content
      end

      private

      def set_task
        @task = TaskSession.where(user: current_user).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { message: "Task not found" }, status: :not_found
      end

      def task_params
        params.permit(:title, :description, :status, :priority, :due_date)
      end

      def task_json(task)
        {
          id: task.id,
          title: task.title || task.session_type,
          description: task.description,
          status: task.status || "pending",
          priority: task.priority || "medium",
          due_date: task.due_date,
          created_at: task.created_at,
          updated_at: task.updated_at
        }
      end

      def task_detail_json(task)
        task_json(task).merge(
          wizard_data: task.wizard_data,
          artifacts: task.artifacts
        )
      end
    end
  end
end
