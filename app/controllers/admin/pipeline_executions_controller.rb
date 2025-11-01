module Admin
  class PipelineExecutionsController < Admin::BaseController
    before_action :set_pipeline_execution, only: [:show, :retry, :cancel]

    def index
      @pipeline_executions = current_entity.pipeline_executions
                                          .includes(:mcp_connection, :agent_executions)
                                          .order(created_at: :desc)

      # Filters
      if params[:status].present?
        @pipeline_executions = @pipeline_executions.where(status: params[:status])
      end

      if params[:priority].present?
        @pipeline_executions = @pipeline_executions.where(priority: params[:priority])
      end

      if params[:ticket_system].present?
        @pipeline_executions = @pipeline_executions.where(ticket_system: params[:ticket_system])
      end

      @pipeline_executions = @pipeline_executions.page(params[:page]).per(20)

      # Stats for dashboard
      @stats = {
        total: current_entity.pipeline_executions.count,
        active: current_entity.pipeline_executions.active.count,
        completed: current_entity.pipeline_executions.completed_successfully.count,
        failed: current_entity.pipeline_executions.failed_executions.count,
        total_cost: current_entity.pipeline_executions.sum(:total_cost),
        total_tokens: current_entity.pipeline_executions.sum(:total_tokens_used)
      }
    end

    def show
      @agent_executions = @pipeline_execution.agent_executions.order(created_at: :asc)
      @artifacts = @pipeline_execution.pipeline_artifacts.order(created_at: :desc)
      @events = @pipeline_execution.pipeline_events.order(created_at: :asc)
      @interactions = @pipeline_execution.pipeline_interactions.order(created_at: :desc)
    end

    def retry
      if @pipeline_execution.status_failed? || @pipeline_execution.status_rolled_back?
        @pipeline_execution.retry!
        redirect_to admin_pipeline_execution_path(@pipeline_execution),
                    notice: 'Pipeline execution queued for retry.'
      else
        redirect_to admin_pipeline_execution_path(@pipeline_execution),
                    alert: 'Can only retry failed or rolled back executions.'
      end
    end

    def cancel
      if @pipeline_execution.terminal_state?
        redirect_to admin_pipeline_execution_path(@pipeline_execution),
                    alert: 'Cannot cancel a completed execution.'
        return
      end

      @pipeline_execution.update!(status: :failed, completed_at: Time.current)
      redirect_to admin_pipeline_execution_path(@pipeline_execution),
                  notice: 'Pipeline execution cancelled.'
    end

    private

    def set_pipeline_execution
      @pipeline_execution = current_entity.pipeline_executions.find(params[:id])
    end
  end
end
