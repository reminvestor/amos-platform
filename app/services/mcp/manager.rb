module MCP
  class Manager
    include Singleton

    def initialize
      @clients = {}
      @mutex = Mutex.new
    end

    # Get or create a client for a server
    def client_for(server_name)
      @mutex.synchronize do
        unless @clients[server_name]
          @clients[server_name] = MCP::Client.new(server_name)
        end

        client = @clients[server_name]

        # Auto-connect if not connected
        unless client.connected?
          client.connect!
        end

        client
      end
    end

    # Call a tool on a specific server
    def call_tool(server_name, tool_name, arguments = {})
      client = client_for(server_name)
      client.call_tool(tool_name, arguments)
    end

    # Read a resource from a specific server
    def read_resource(server_name, uri)
      client = client_for(server_name)
      client.read_resource(uri)
    end

    # List all tools across all configured servers
    def list_all_tools
      config = YAML.load_file(Rails.root.join('config', 'mcp_servers.yml'))
      tools = []

      config['servers'].each do |server_name, _config|
        begin
          client = client_for(server_name)
          server_tools = client.list_tools
          tools += server_tools.map { |t| t.merge('server' => server_name) }
        rescue => e
          Rails.logger.warn "Could not list tools for #{server_name}: #{e.message}"
        end
      end

      tools
    end

    # Get tool schema for Claude tool calling
    def get_claude_tools
      all_tools = list_all_tools

      all_tools.map do |tool|
        {
          name: "#{tool['server']}_#{tool['name']}",
          description: tool['description'] || "Tool from #{tool['server']} MCP server",
          input_schema: tool['inputSchema'] || {
            type: 'object',
            properties: {},
            required: []
          },
          _mcp_server: tool['server'],
          _mcp_tool_name: tool['name']
        }
      end
    end

    # Execute a tool call from Claude
    def execute_claude_tool(tool_name, arguments)
      # Tool name format: "server_toolname"
      parts = tool_name.split('_', 2)

      if parts.length < 2
        return {
          success: false,
          error: "Invalid tool name format. Expected 'server_toolname'"
        }
      end

      server_name = parts[0]
      mcp_tool_name = parts[1]

      call_tool(server_name, mcp_tool_name, arguments)
    end

    # Disconnect all clients
    def disconnect_all!
      @mutex.synchronize do
        @clients.each do |_name, client|
          client.disconnect! rescue nil
        end
        @clients.clear
      end
    end

    # Health check for all servers
    def health_check
      config = YAML.load_file(Rails.root.join('config', 'mcp_servers.yml'))
      results = {}

      config['servers'].each do |server_name, _config|
        begin
          client = client_for(server_name)
          results[server_name] = {
            status: 'connected',
            tools_count: client.list_tools.length,
            resources_count: client.list_resources.length
          }
        rescue => e
          results[server_name] = {
            status: 'error',
            error: e.message
          }
        end
      end

      results
    end

    # Reconnect a specific server
    def reconnect!(server_name)
      @mutex.synchronize do
        if @clients[server_name]
          @clients[server_name].disconnect! rescue nil
          @clients.delete(server_name)
        end

        client = MCP::Client.new(server_name)
        client.connect!
        @clients[server_name] = client
      end
    end
  end
end
