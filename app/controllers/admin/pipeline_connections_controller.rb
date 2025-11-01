module Admin
  class PipelineConnectionsController < Admin::BaseController
    before_action :set_pipeline_connection, only: [:show, :edit, :update, :destroy, :test]

    def index
      @pipeline_connections = current_entity.mcp_connections
                                           .order(created_at: :desc)
                                           .page(params[:page])
                                           .per(20)

      # Filter by system type if provided
      if params[:system_type].present?
        @pipeline_connections = @pipeline_connections.where(system_type: params[:system_type])
      end
    end

    def show
      @recent_executions = @pipeline_connection.pipeline_executions
                                               .order(created_at: :desc)
                                               .limit(10)
    end

    def new
      @pipeline_connection = current_entity.mcp_connections.new
    end

    def create
      @pipeline_connection = current_entity.mcp_connections.new(pipeline_connection_params)

      if @pipeline_connection.save
        redirect_to admin_pipeline_connection_path(@pipeline_connection),
                    notice: 'Pipeline connection created successfully.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @pipeline_connection.update(pipeline_connection_params)
        redirect_to admin_pipeline_connection_path(@pipeline_connection),
                    notice: 'Pipeline connection updated successfully.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @pipeline_connection.pipeline_executions.any?
        redirect_to admin_pipeline_connections_path,
                    alert: 'Cannot delete connection with existing pipeline executions.'
        return
      end

      @pipeline_connection.destroy
      redirect_to admin_pipeline_connections_path,
                  notice: 'Pipeline connection deleted successfully.'
    end

    def test
      result = @pipeline_connection.test_connection!

      if result[:success]
        @pipeline_connection.mark_healthy!
        redirect_to admin_pipeline_connection_path(@pipeline_connection),
                    notice: 'Connection test successful!'
      else
        @pipeline_connection.mark_unhealthy!(result[:error])
        redirect_to admin_pipeline_connection_path(@pipeline_connection),
                    alert: "Connection test failed: #{result[:error]}"
      end
    end

    private

    def set_pipeline_connection
      @pipeline_connection = current_entity.mcp_connections.find(params[:id])
    end

    def pipeline_connection_params
      params.require(:mcp_connection).permit(
        :system_type,
        :name,
        :status,
        config: {},
        metadata: {}
      )
    end
  end
end
