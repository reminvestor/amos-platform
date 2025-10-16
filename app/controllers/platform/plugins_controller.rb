module Platform
  class PluginsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_developer_mode
    before_action :set_plugin, only: [ :show, :edit, :update, :destroy, :test ]

    def index
      @plugins = current_user.custom_plugins.includes(:entity)

      # Group by type
      @agents = @plugins.agents
      @tools = @plugins.tools
      @models = @plugins.models
      @workflows = @plugins.workflows
    end

    def new
      @plugin = current_user.custom_plugins.build(
        entity: current_entity,
        plugin_type: params[:type] || "tool"
      )
    end

    def create
      @plugin = current_user.custom_plugins.build(plugin_params)
      @plugin.entity = current_entity

      if @plugin.save
        redirect_to platform_plugin_path(@plugin),
                    notice: "#{@plugin.plugin_type.titleize} created successfully!"
      else
        render :new
      end
    end

    def show
      @usage_stats = @plugin.usage_stats(30.days)
      @resource_usage = @plugin.resource_usage(30.days)
    end

    def edit
    end

    def update
      if @plugin.update(plugin_params)
        redirect_to platform_plugin_path(@plugin),
                    notice: "#{@plugin.plugin_type.titleize} updated successfully!"
      else
        render :edit
      end
    end

    def destroy
      @plugin.destroy
      redirect_to platform_plugins_path,
                  notice: "Plugin deleted successfully."
    end

    def test
      # Test plugin in sandbox
      result = Agents::Platform::PluginManager.instance.execute_plugin(
        @plugin.plugin_id,
        :test,
        test_params,
        { user: current_user, entity: current_entity }
      )

      render json: result
    end

    # Upload custom agent code
    def upload_agent
      code = params[:code]

      result = Agents::Platform::PluginManager.instance.load_custom_agent(
        code,
        user: current_user,
        entity: current_entity
      )

      if result[:success]
        redirect_to platform_plugins_path,
                    notice: "Agent uploaded successfully!"
      else
        redirect_to new_platform_plugin_path(type: "agent"),
                    alert: "Upload failed: #{result[:error]}"
      end
    end

    # Upload custom tool code
    def upload_tool
      code = params[:code]

      result = Agents::Platform::PluginManager.instance.load_custom_tool(
        code,
        user: current_user,
        entity: current_entity
      )

      if result[:success]
        redirect_to platform_plugins_path,
                    notice: "Tool uploaded successfully!"
      else
        redirect_to new_platform_plugin_path(type: "tool"),
                    alert: "Upload failed: #{result[:error]}"
      end
    end

    # Configure custom model
    def configure_model
      model_config = {
        name: params[:name],
        type: params[:model_type],
        endpoint: params[:endpoint],
        api_key: params[:api_key],
        base_model: params[:base_model],
        parameters: params[:parameters]
      }

      result = Agents::Platform::ModelRegistry.instance.register_custom_model(
        user: current_user,
        entity: current_entity,
        model_config: model_config
      )

      if result[:success]
        redirect_to platform_plugins_path,
                    notice: "Model configured successfully!"
      else
        redirect_to new_platform_plugin_path(type: "model"),
                    alert: "Configuration failed: #{result[:error]}"
      end
    end

    private

    def set_plugin
      @plugin = current_user.custom_plugins.find(params[:id])
    end

    def ensure_developer_mode
      unless current_user.developer_mode?
        redirect_to root_path,
                    alert: "Developer mode required. Contact support to enable."
      end
    end

    def plugin_params
      params.require(:custom_plugin).permit(
        :plugin_type,
        :code,
        spec: {}
      )
    end

    def test_params
      params.permit(:method, args: {})
    end
  end
end
