class AgentPluginsController < ApplicationController
  include Authorizable
  before_action :authenticate_user!
  layout 'customer_admin'
  before_action :set_agent, only: [:show, :edit, :update, :destroy]
  before_action :authorize_destroy!, only: [:destroy]

  def index
    @my_agents = AgentPlugin.where(entity: current_entity).order(created_at: :desc)
    @system_agents = AgentPlugin.system_wide.active
  end

  def show
  end

  def new
    @agent = AgentPlugin.new
  end

  def create
    @agent = AgentPlugin.new(agent_params)
    @agent.entity = current_entity
    @agent.status = 'draft'
    
    if @agent.save
      redirect_to agent_plugin_path(@agent), notice: 'Agent created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @agent.update(agent_params)
      redirect_to agent_plugin_path(@agent), notice: 'Agent updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @agent.destroy
    redirect_to agent_plugins_path, notice: 'Agent deleted successfully.'
  end

  private

  def set_agent
    @agent = AgentPlugin.where(entity: current_entity).find(params[:id])
  end

  def agent_params
    params.require(:agent_plugin).permit(:name, :description, :role, :system_prompt, :status)
  end
end

