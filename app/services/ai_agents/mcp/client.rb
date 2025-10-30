require 'open3'
require 'json'

module AiAgents::Mcp
  class Client
    attr_reader :server_name, :config, :process_stdin, :process_stdout, :process_stderr, :thread

    def initialize(server_name)
      @server_name = server_name
      @config = load_config(server_name)
      @request_id = 0
      @pending_requests = {}
      @tools = []
      @resources = []
      @connected = false
    end

    def connect!
      return true if @connected

      command = build_command
      env = build_env

      Rails.logger.info "Starting MCP server: #{server_name}"
      Rails.logger.debug "Command: #{command.join(' ')}"

      @process_stdin, @process_stdout, @process_stderr, @thread = Open3.popen3(env, *command)

      # Send initialize request
      initialize_result = send_request('initialize', {
        protocolVersion: '2024-11-05',
        capabilities: {
          roots: { listChanged: true },
          sampling: {}
        },
        clientInfo: {
          name: 'AMOS Pipeline',
          version: '1.0.0'
        }
      })

      unless initialize_result['capabilities']
        raise "MCP server #{server_name} failed to initialize"
      end

      # Send initialized notification
      send_notification('notifications/initialized')

      # List available tools
      tools_result = send_request('tools/list')
      @tools = tools_result['tools'] || []

      # List available resources
      resources_result = send_request('resources/list')
      @resources = resources_result['resources'] || []

      @connected = true
      Rails.logger.info "MCP server #{server_name} connected. Tools: #{@tools.length}, Resources: #{@resources.length}"

      true
    rescue => e
      Rails.logger.error "Failed to connect to MCP server #{server_name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      cleanup
      false
    end

    def disconnect!
      return unless @connected

      send_notification('notifications/cancelled')
      cleanup
      @connected = false
    end

    def call_tool(tool_name, arguments = {})
      raise "Not connected to MCP server" unless @connected
      raise "Tool #{tool_name} not available" unless tool_available?(tool_name)

      result = send_request('tools/call', {
        name: tool_name,
        arguments: arguments
      })

      {
        success: !result['isError'],
        content: result['content'],
        is_error: result['isError']
      }
    rescue => e
      Rails.logger.error "MCP tool call failed (#{server_name}/#{tool_name}): #{e.message}"
      {
        success: false,
        error: e.message,
        is_error: true
      }
    end

    def read_resource(uri)
      raise "Not connected to MCP server" unless @connected

      result = send_request('resources/read', {
        uri: uri
      })

      {
        success: true,
        contents: result['contents']
      }
    rescue => e
      Rails.logger.error "MCP resource read failed (#{server_name}/#{uri}): #{e.message}"
      {
        success: false,
        error: e.message
      }
    end

    def list_tools
      @tools
    end

    def list_resources
      @resources
    end

    def tool_available?(tool_name)
      @tools.any? { |t| t['name'] == tool_name }
    end

    def get_tool_schema(tool_name)
      @tools.find { |t| t['name'] == tool_name }
    end

    def connected?
      @connected
    end

    private

    def load_config(server_name)
      config_file = Rails.root.join('config', 'mcp_servers.yml')
      unless File.exist?(config_file)
        raise "MCP config file not found: #{config_file}"
      end

      config = YAML.load_file(config_file)
      server_config = config['servers'][server_name.to_s]

      unless server_config
        raise "MCP server '#{server_name}' not found in config"
      end

      server_config.deep_symbolize_keys
    end

    def build_command
      command = [@config[:command]]
      command += @config[:args] if @config[:args]
      command
    end

    def build_env
      env = ENV.to_h.dup

      if @config[:env]
        @config[:env].each do |key, value|
          # Substitute environment variables
          expanded_value = value.gsub(/\$\{(\w+)\}/) { ENV[$1] || '' }
          env[key.to_s] = expanded_value
        end
      end

      env
    end

    def send_request(method, params = {})
      request_id = next_request_id

      message = {
        jsonrpc: '2.0',
        id: request_id,
        method: method,
        params: params
      }

      write_message(message)

      # Read response
      response = read_message

      if response['error']
        error_msg = response['error']['message'] || 'Unknown error'
        raise "MCP request failed: #{error_msg}"
      end

      response['result'] || {}
    rescue => e
      Rails.logger.error "MCP request error (#{method}): #{e.message}"
      raise
    end

    def send_notification(method, params = {})
      message = {
        jsonrpc: '2.0',
        method: method,
        params: params
      }

      write_message(message)
    end

    def write_message(message)
      json = message.to_json
      @process_stdin.puts(json)
      @process_stdin.flush
    end

    def read_message
      line = @process_stdout.gets
      raise "MCP server closed connection" unless line

      JSON.parse(line)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse MCP response: #{line}"
      raise "Invalid JSON from MCP server: #{e.message}"
    end

    def next_request_id
      @request_id += 1
    end

    def cleanup
      @process_stdin&.close
      @process_stdout&.close
      @process_stderr&.close

      if @thread
        # Give process 5 seconds to exit gracefully
        unless @thread.join(5)
          Process.kill('TERM', @thread.pid) rescue nil
          @thread.join(2)
          Process.kill('KILL', @thread.pid) rescue nil
        end
      end
    rescue => e
      Rails.logger.error "Error during MCP cleanup: #{e.message}"
    end
  end
end
