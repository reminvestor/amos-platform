# Admin controller for managing Agent Plugins
#
# Provides CRUD operations and management features for database-backed agents:
# - List/search/filter agents
# - Create/edit/delete agents
# - Configure capabilities and tools
# - Test agent execution
# - View analytics and performance stats
# - Clone agents
# - Import/export agents
#
class Admin::AgentPluginsController < Admin::BaseController
  before_action :set_agent_plugin, only: [:show, :edit, :update, :destroy, :activate, :deactivate, :test, :run_test, :clone]
  before_action :set_agent_service, only: [:index, :show, :test, :run_test, :analytics]

  # GET /admin/agent_plugins
  def index
    @filter_status = params[:status] || 'all'
    @filter_role = params[:role]
    @search = params[:search]

    @agent_plugins = AgentPlugin.all

    # Apply filters
    @agent_plugins = @agent_plugins.where(status: @filter_status) unless @filter_status == 'all'
    @agent_plugins = @agent_plugins.by_role(@filter_role) if @filter_role.present?
    @agent_plugins = @agent_plugins.where('name ILIKE ?', "%#{@search}%") if @search.present?

    # Pagination
    @agent_plugins = @agent_plugins.order(priority: :desc, created_at: :desc)
                                   .page(params[:page])
                                   .per(20)

    # Stats for the dashboard
    @stats = {
      total: AgentPlugin.count,
      active: AgentPlugin.active.count,
      draft: AgentPlugin.where(status: 'draft').count,
      deprecated: AgentPlugin.where(status: 'deprecated').count,
      system_wide: AgentPlugin.system_wide.count,
      entity_specific: AgentPlugin.entity_specific.count
    }
  end

  # GET /admin/agent_plugins/:id
  def show
    @executions = @agent_plugin.agent_plugin_executions
                               .includes(:user, :workflow_execution)
                               .order(created_at: :desc)
                               .limit(20)

    @stats = @agent_plugin.execution_stats
    @capabilities = @agent_plugin.agent_capabilities
    @tools = @agent_plugin.agent_tools
    @template_bindings = @agent_plugin.agent_template_bindings.includes(:workflow_template)
  end

  # GET /admin/agent_plugins/new
  def new
    @agent_plugin = AgentPlugin.new(
      status: 'draft',
      priority: 50,
      version: '1.0.0'
    )

    # Don't pre-build capabilities/tools - users can add them via UI if needed
  end

  # POST /admin/agent_plugins
  def create
    @agent_plugin = AgentPlugin.new(agent_plugin_params)

    if @agent_plugin.save
      redirect_to admin_agent_plugin_path(@agent_plugin),
                  notice: "Agent plugin '#{@agent_plugin.name}' created successfully!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /admin/agent_plugins/:id/edit
  def edit
    # Don't pre-build capabilities/tools - users can add them via UI if needed
  end

  # PATCH /admin/agent_plugins/:id
  def update
    if @agent_plugin.update(agent_plugin_params)
      redirect_to admin_agent_plugin_path(@agent_plugin),
                  notice: "Agent plugin '#{@agent_plugin.name}' updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /admin/agent_plugins/:id
  def destroy
    name = @agent_plugin.name

    if @agent_plugin.destroy
      redirect_to admin_agent_plugins_path, notice: "Agent plugin '#{name}' deleted successfully!"
    else
      redirect_to admin_agent_plugin_path(@agent_plugin),
                  alert: "Failed to delete agent plugin: #{@agent_plugin.errors.full_messages.join(', ')}"
    end
  end

  # POST /admin/agent_plugins/:id/activate
  def activate
    @agent_plugin.activate!
    redirect_to admin_agent_plugin_path(@agent_plugin),
                notice: "Agent plugin '#{@agent_plugin.name}' activated!"
  end

  # POST /admin/agent_plugins/:id/deactivate
  def deactivate
    @agent_plugin.deactivate!
    redirect_to admin_agent_plugin_path(@agent_plugin),
                notice: "Agent plugin '#{@agent_plugin.name}' deactivated!"
  end

  # GET /admin/agent_plugins/:id/test
  def test
    # Show test interface
  end

  # POST /admin/agent_plugins/:id/test
  def run_test
    @agent_plugin = AgentPlugin.find(params[:id])

    # Parse test input
    test_context = JSON.parse(params[:test_context] || '{}')

    # Override model if specified in test
    if params[:test_model].present?
      test_context[:config] ||= {}
      test_context[:config][:model] = params[:test_model]
    end

    # Run the test (allow testing draft agents)
    begin
      agent_instance = @agent_service.instantiate_agent(@agent_plugin, test_context, skip_status_check: true)

      result = if params[:test_method] == 'execute_goal'
                 agent_instance.achieve_goal(params[:test_goal], test_context)
               else
                 agent_instance.run(params[:test_prompt])
               end

      render json: {
        success: true,
        result: result,
        agent: @agent_plugin.name
      }
    rescue => e
      render json: {
        success: false,
        error: e.message,
        backtrace: e.backtrace.first(10)
      }, status: :unprocessable_entity
    end
  end

  # POST /admin/agent_plugins/:id/clone
  def clone
    cloned = @agent_service.clone_agent(
      @agent_plugin,
      new_name: params[:new_name] || "#{@agent_plugin.name} (Copy)",
      entity: params[:entity_id].present? ? Entity.find(params[:entity_id]) : nil
    )

    redirect_to edit_admin_agent_plugin_path(cloned),
                notice: "Agent plugin cloned! Edit the details below."
  rescue => e
    redirect_to admin_agent_plugin_path(@agent_plugin),
                alert: "Failed to clone agent: #{e.message}"
  end

  # GET /admin/agent_plugins/analytics
  def analytics
    @time_range = (params[:days] || 30).to_i.days.ago

    # Get execution stats by agent
    @execution_stats = AgentPluginExecution
                        .where('created_at >= ?', @time_range)
                        .group('agent_plugin_id')
                        .select(
                          'agent_plugin_id',
                          'COUNT(*) as total_executions',
                          'AVG(NULLIF(duration_ms, 0)) as avg_duration',
                          'SUM(tokens_used) as total_tokens',
                          'COUNT(CASE WHEN status = \'completed\' THEN 1 END) as successful',
                          'COUNT(CASE WHEN status = \'failed\' THEN 1 END) as failed'
                        )

    # Map to agent names
    agent_map = AgentPlugin.pluck(:id, :name).to_h
    @execution_stats = @execution_stats.map do |stat|
      {
        agent_name: agent_map[stat.agent_plugin_id],
        total: stat.total_executions.to_i,
        avg_duration: stat.avg_duration&.to_i || 0,
        total_tokens: stat.total_tokens || 0,
        success_rate: calculate_success_rate(stat.successful, stat.total_executions)
      }
    end.sort_by { |s| -s[:total] }

    # Chart data for executions over time
    @execution_timeline = generate_execution_timeline(@time_range)
  end

  private

  def set_agent_plugin
    @agent_plugin = AgentPlugin.find(params[:id])
  end

  def set_agent_service
    @agent_service = AgentPluginService.new(
      entity: current_entity,
      user: current_user
    )
  end

  def agent_plugin_params
    params.require(:agent_plugin).permit(
      :name,
      :slug,
      :role,
      :description,
      :version,
      :status,
      :agent_class,
      :priority,
      :entity_id,
      :ai_model,
      :model_config,
      :configuration,
      :system_prompt,
      :capabilities_definition,
      agent_capabilities_attributes: [:id, :capability_name, :contract_schema, :implementation_notes, :_destroy],
      agent_tools_attributes: [:id, :tool_name, :required, :_destroy]
    )
  end

  def calculate_success_rate(successful, total)
    return 0 if total.zero?
    ((successful.to_f / total) * 100).round(2)
  end

  def generate_execution_timeline(since)
    # Group executions by day and sort chronologically
    executions = AgentPluginExecution
      .where('created_at >= ?', since)
      .group("DATE(created_at)")
      .count

    # Sort by date (keys are Date objects)
    executions.sort_by { |date, _| date }
      .to_h
  end
end
