module Admin
  class ToolsController < BaseController
    def index
      @tools = ToolDefinition.all.order(created_at: :desc)
    end

    def new
      @tool = ToolDefinition.new
    end

    def create
      @tool = ToolDefinition.new(tool_params)
      
      # Set code to nil if not ruby type to avoid validation error
      @tool.code = nil if @tool.execution_type != 'ruby_code'
      @tool.api_config = nil if @tool.execution_type != 'http_request'

      if @tool.save
        # Refresh catalog immediately
        Tools::ToolCatalog.instance.refresh_dynamic_tools!
        redirect_to admin_tools_path, notice: 'Tool created successfully'
      else
        render :new
      end
    end

    def edit
      @tool = ToolDefinition.find(params[:id])
    end

    def update
      @tool = ToolDefinition.find(params[:id])
      if @tool.update(tool_params)
        # Refresh catalog
        Tools::ToolCatalog.instance.refresh_dynamic_tools!
        redirect_to admin_tools_path, notice: 'Tool updated successfully'
      else
        render :edit
      end
    end

    def destroy
      @tool = ToolDefinition.find(params[:id])
      @tool.destroy
      
      # Refresh catalog
      Tools::ToolCatalog.instance.refresh_dynamic_tools!
      
      redirect_to admin_tools_path, notice: 'Tool deleted successfully'
    end

    private

    def tool_params
      # For JSON fields, we might need to parse them from string if they come from text area
      # But usually Rails handles JSON types fine if passed as hash structure
      params.require(:tool_definition).permit(
        :name, :description, :execution_type, :code, :admin_only,
        parameters: {}, api_config: {}
      )
    end
  end
end

