# Concern to help migrate controllers to use ScoutGenericToolsServiceV2
module ScoutToolsV2
  extend ActiveSupport::Concern
  
  included do
    # Helper method to get the appropriate Scout service
    def scout_service(agent_loadout: nil)
      @scout_service ||= ScoutGenericToolsServiceV2.new(
        current_user,
        current_entity,
        session[:scout_session_id],
        agent_loadout: agent_loadout
      )
    end
    
    # Process a message with tools (streaming version)
    def process_with_tools_streaming(message, progress_callback, history = [], canvas = nil, agent_loadout: nil)
      service = scout_service(agent_loadout: agent_loadout)
      service.process_message_with_tools_streaming(message, progress_callback, history, canvas)
    end
    
    # Execute a specific tool
    def execute_tool(tool_name, args, agent_loadout: nil)
      service = scout_service(agent_loadout: agent_loadout)
      service.execute_tool_by_name(tool_name, args)
    end
    
    # Get tools for a specific agent role
    def tools_for_role(role)
      loadout = AgentLoadout.new(agent_role: role)
      Tools::ToolCatalog.instance.get_bedrock_tools(agent_loadout: loadout)
    end
    
    # Check if we should use V2 (can be toggled via env var during migration)
    def use_v2_service?
      ENV['USE_SCOUT_V2'].present? || Rails.env.development?
    end
  end
end
