class ToolsController < ApplicationController
  include Authorizable
  before_action :authenticate_user!
  layout 'customer_admin'
  before_action :set_tool, only: [:show, :edit, :update, :destroy]
  before_action :authorize_destroy!, only: [:destroy]

  def index
    @my_tools = ToolDefinition.where(created_by: current_user).order(created_at: :desc)
    @public_tools = ToolDefinition.public_tools
  end

  def show
  end

  def new
    @tool = ToolDefinition.new
  end

  def create
    @tool = ToolDefinition.new(tool_params)
    @tool.created_by = current_user
    
    if @tool.save
      redirect_to tool_path(@tool), notice: 'Tool created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @tool.update(tool_params)
      redirect_to tool_path(@tool), notice: 'Tool updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @tool.destroy
    redirect_to tools_path, notice: 'Tool deleted successfully.'
  end

  private

  def set_tool
    @tool = ToolDefinition.where(created_by: current_user).find(params[:id])
  end

  def tool_params
    params.require(:tool_definition).permit(:name, :description, :execution_type, :code, :api_config, :parameters)
  end
end

