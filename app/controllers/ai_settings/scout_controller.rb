class AiSettings::ScoutController < ApplicationController
  before_action :authenticate_user!
  before_action :require_entity_admin!
  before_action :set_configuration

  layout "customer_admin"

  def show
    redirect_to chat_mode_path, status: :moved_permanently
  end

  def update
    if @configuration.update(configuration_params)
      redirect_to chat_mode_path, notice: "Scout settings updated successfully."
    else
      redirect_to chat_mode_path, alert: "Failed to update settings: #{@configuration.errors.full_messages.join(', ')}"
    end
  end

  private

  def require_entity_admin!
    unless current_user.entity_admin?
      redirect_to chat_mode_path, alert: "You need to be an entity admin to access AI settings."
    end
  end

  def set_configuration
    @configuration = ScoutLoadoutConfiguration.for_entity(current_entity)
  end

  def configuration_params
    params.require(:scout_loadout_configuration).permit(
      :use_tiered_discovery,
      :max_discovered_tools,
      budgets: [:max_tokens, :max_tool_calls, :timeout_seconds],
      tool_allowlist: [],
      canvas_allowlist: []
    )
  end

  def load_available_tools
    # Get all class-based tools from the catalog
    catalog = Tools::ToolCatalog.instance
    class_tools = catalog.all_tools.map do |name, info|
      next if info[:type] == :definition # Skip dynamic tools here
      
      {
        name: name.to_s,
        description: info[:metadata][:description] || "No description",
        category: categorize_tool(name.to_s),
        type: :class,
        enabled: @configuration.tool_allowed?(name.to_s)
      }
    end.compact

    # Get dynamic tools that are marked as scout_accessible
    dynamic_tools = ToolDefinition.scout_accessible.for_entity(current_entity).map do |tool|
      {
        name: tool.name,
        description: tool.description || "No description",
        category: "Custom Tools",
        type: :dynamic,
        enabled: @configuration.tool_allowed?(tool.name)
      }
    end

    (class_tools + dynamic_tools).sort_by { |t| t[:name] }
  end

  def categorize_tools(tools)
    tools.group_by { |t| t[:category] }.sort_by { |cat, _| cat }
  end

  def categorize_tool(name)
    case name
    when /^get_|^list_|^query_|^search_|^retrieve_|^read_/
      "Data & Queries"
    when /^create_|^update_|^delete_/
      "Data Modification"
    when /^execute_|^invoke_|^delegate_/
      "Execution & Delegation"
    when /canvas|visualization/
      "UI & Visualization"
    when /integration|connection|operation/
      "Integrations"
    when /agent|plugin/
      "Agents"
    when /document|rag|knowledge/
      "Documents & Knowledge"
    when /history|message/
      "Conversation"
    else
      "Other"
    end
  end
end

