module Agents
  module Platform
    class PluginManager
      include Singleton
      
      def initialize
        @plugins = {}
        @sandboxes = {}
        @validators = {}
        @mutex = Mutex.new
      end
      
      # Register a new plugin (agent, tool, or model)
      def register_plugin(plugin_spec)
        validate_plugin!(plugin_spec)
        
        plugin_id = plugin_spec[:id] || SecureRandom.uuid
        
        @mutex.synchronize do
          @plugins[plugin_id] = {
            spec: plugin_spec,
            status: :pending,
            sandbox: create_sandbox(plugin_spec),
            loaded_at: nil,
            metadata: extract_metadata(plugin_spec)
          }
        end
        
        # Async validation and loading
        PluginLoaderJob.perform_async(plugin_id)
        
        plugin_id
      end
      
      # Load user-uploaded agent
      def load_custom_agent(agent_code, user:, entity:)
        # Validate code safety
        validation = validate_agent_code(agent_code)
        return validation unless validation[:safe]
        
        # Create isolated environment
        sandbox = AgentSandbox.new(
          user: user,
          entity: entity,
          resource_limits: get_resource_limits(user)
        )
        
        # Parse agent definition
        agent_spec = parse_agent_definition(agent_code)
        
        # Create custom agent class
        custom_class = create_custom_agent_class(agent_spec, sandbox)
        
        # Register with platform
        register_custom_agent(custom_class, agent_spec, user)
        
        {
          success: true,
          agent_id: agent_spec[:id],
          capabilities: agent_spec[:capabilities]
        }
      rescue => e
        Rails.logger.error "Failed to load custom agent: #{e.message}"
        { success: false, error: e.message }
      end
      
      # Load user-uploaded tool
      def load_custom_tool(tool_code, user:, entity:)
        # Validate tool code
        validation = validate_tool_code(tool_code)
        return validation unless validation[:safe]
        
        # Create tool wrapper
        tool_spec = parse_tool_definition(tool_code)
        
        # Wrap in secure executor
        secure_tool = create_secure_tool(tool_spec, user, entity)
        
        # Register with tool catalog
        ::Tools::ToolCatalog.instance.register(secure_tool)
        
        # Track ownership
        CustomPlugin.create!(
          user: user,
          entity: entity,
          plugin_type: 'tool',
          plugin_id: tool_spec[:name],
          spec: tool_spec,
          code: tool_code,
          status: 'active'
        )
        
        {
          success: true,
          tool_name: tool_spec[:name],
          description: tool_spec[:description]
        }
      end
      
      # Load user-uploaded model
      def load_custom_model(model_config, user:, entity:)
        # Validate model configuration
        validation = validate_model_config(model_config)
        return validation unless validation[:valid]
        
        model_spec = {
          id: SecureRandom.uuid,
          name: model_config[:name],
          type: model_config[:type], # 'huggingface', 'ollama', 'custom_api'
          endpoint: model_config[:endpoint],
          api_key_encrypted: encrypt_api_key(model_config[:api_key]),
          parameters: model_config[:parameters],
          cost_per_token: model_config[:cost_per_token] || 0.001,
          rate_limits: model_config[:rate_limits]
        }
        
        # Test model connectivity
        test_result = test_model_connection(model_spec)
        return test_result unless test_result[:success]
        
        # Create model adapter
        adapter = create_model_adapter(model_spec)
        
        # Register with AI service registry
        AIServiceRegistry.register_model(adapter, user: user, entity: entity)
        
        # Save configuration
        CustomModel.create!(
          user: user,
          entity: entity,
          model_id: model_spec[:id],
          spec: model_spec,
          status: 'active'
        )
        
        {
          success: true,
          model_id: model_spec[:id],
          name: model_spec[:name]
        }
      end
      
      # Get available plugins for user
      def available_plugins(user:, plugin_type: nil)
        # Get system plugins
        system_plugins = get_system_plugins(plugin_type)
        
        # Get user's custom plugins
        user_plugins = CustomPlugin.where(user: user, status: 'active')
        user_plugins = user_plugins.where(plugin_type: plugin_type) if plugin_type
        
        # Get shared/marketplace plugins
        shared_plugins = get_shared_plugins(user, plugin_type)
        
        {
          system: system_plugins,
          custom: user_plugins.map(&:to_plugin_info),
          shared: shared_plugins
        }
      end
      
      # Execute plugin in sandbox
      def execute_plugin(plugin_id, method, args, context)
        plugin = @plugins[plugin_id]
        raise "Plugin not found: #{plugin_id}" unless plugin
        raise "Plugin not active" unless plugin[:status] == :active
        
        # Execute in sandbox with resource limits
        sandbox = plugin[:sandbox]
        
        sandbox.execute do |env|
          # Inject context
          env.context = context
          env.user = context[:user]
          env.entity = context[:entity]
          
          # Set resource limits
          env.set_limits(
            memory: '512MB',
            cpu_time: 30.seconds,
            api_calls: 100,
            network_access: plugin[:spec][:requires_network]
          )
          
          # Execute method
          result = env.call_method(method, args)
          
          # Track usage
          track_plugin_usage(plugin_id, env.resource_usage)
          
          result
        end
      rescue Sandbox::SecurityError => e
        Rails.logger.error "Security violation in plugin #{plugin_id}: #{e.message}"
        { error: "Security violation: #{e.message}" }
      rescue => e
        Rails.logger.error "Plugin execution error: #{e.message}"
        { error: "Execution error: #{e.message}" }
      end
      
      private
      
      def validate_plugin!(spec)
        raise "Plugin spec must include type" unless spec[:type]
        raise "Plugin spec must include code or reference" unless spec[:code] || spec[:reference]
        
        case spec[:type]
        when 'agent'
          validate_agent_spec!(spec)
        when 'tool'
          validate_tool_spec!(spec)
        when 'model'
          validate_model_spec!(spec)
        else
          raise "Unknown plugin type: #{spec[:type]}"
        end
      end
      
      def validate_agent_code(code)
        # Security scanning
        security_check = SecurityScanner.scan_code(code)
        return { safe: false, errors: security_check[:violations] } unless security_check[:safe]
        
        # Syntax validation
        begin
          RubyParser.parse(code)
        rescue => e
          return { safe: false, errors: ["Syntax error: #{e.message}"] }
        end
        
        # Check for forbidden patterns
        forbidden = check_forbidden_patterns(code)
        return { safe: false, errors: forbidden } if forbidden.any?
        
        # Check resource usage
        estimated_resources = estimate_resource_usage(code)
        if estimated_resources[:high_risk]
          return { safe: false, errors: ["Resource usage too high"] }
        end
        
        { safe: true }
      end
      
      def validate_tool_code(code)
        validation = validate_agent_code(code) # Same base validation
        return validation unless validation[:safe]
        
        # Additional tool-specific validation
        tool_ast = RubyParser.parse(code)
        
        # Must have execute method
        unless has_method?(tool_ast, :execute)
          return { safe: false, errors: ["Tool must implement execute method"] }
        end
        
        # Must have metadata method
        unless has_method?(tool_ast, :metadata)
          return { safe: false, errors: ["Tool must implement metadata method"] }
        end
        
        { safe: true }
      end
      
      def validate_model_config(config)
        errors = []
        
        # Required fields
        %i[name type endpoint].each do |field|
          errors << "Missing required field: #{field}" unless config[field]
        end
        
        # Validate endpoint
        if config[:endpoint]
          begin
            uri = URI.parse(config[:endpoint])
            errors << "Invalid endpoint URL" unless uri.scheme && uri.host
          rescue
            errors << "Invalid endpoint URL format"
          end
        end
        
        # Validate type
        valid_types = %w[huggingface ollama openai anthropic custom_api]
        unless valid_types.include?(config[:type])
          errors << "Invalid model type. Must be one of: #{valid_types.join(', ')}"
        end
        
        {
          valid: errors.empty?,
          errors: errors
        }
      end
      
      def create_sandbox(plugin_spec)
        Sandbox.new(
          name: "plugin_#{plugin_spec[:id]}",
          permissions: plugin_spec[:permissions] || [],
          resource_limits: plugin_spec[:resource_limits] || default_resource_limits
        )
      end
      
      def parse_agent_definition(code)
        # Extract agent metadata from code comments or decorators
        metadata = extract_metadata_from_code(code)
        
        {
          id: metadata[:id] || SecureRandom.uuid,
          name: metadata[:name] || 'Custom Agent',
          role: metadata[:role] || :custom,
          capabilities: metadata[:capabilities] || [],
          code: code,
          version: metadata[:version] || '1.0.0'
        }
      end
      
      def create_custom_agent_class(agent_spec, sandbox)
        # Create a new class that inherits from BaseAgent
        Class.new(Agents::Base::BaseAgent) do
          # Set sandbox
          define_method :initialize do |**args|
            super(
              role: agent_spec[:role],
              capabilities: agent_spec[:capabilities],
              **args
            )
            @sandbox = sandbox
            @custom_code = agent_spec[:code]
          end
          
          # Override execute to run in sandbox
          define_method :execute do
            @sandbox.execute do |env|
              env.eval(@custom_code)
              env.call_method(:execute, self)
            end
          end
          
          # Add safety wrapper for all methods
          define_method :method_missing do |method, *args, &block|
            if @sandbox.allowed_method?(method)
              @sandbox.execute do |env|
                env.call_method(method, *args, &block)
              end
            else
              raise SecurityError, "Method not allowed: #{method}"
            end
          end
        end
      end
      
      def create_secure_tool(tool_spec, user, entity)
        Class.new(Tools::BaseTool) do
          define_singleton_method :metadata do
            tool_spec[:metadata].merge(
              custom: true,
              owner_id: user.id,
              entity_id: entity.id
            )
          end
          
          define_method :execute do |args|
            # Validate permissions
            unless can_execute?(args[:user], args[:entity])
              return { success: false, error: "Permission denied" }
            end
            
            # Execute in sandbox
            PluginManager.instance.execute_plugin(
              tool_spec[:id],
              :execute,
              args,
              { user: user, entity: entity }
            )
          end
          
          private
          
          define_method :can_execute? do |exec_user, exec_entity|
            # Check if user has permission to use this tool
            return true if exec_user.id == user.id
            return true if exec_entity.id == entity.id && tool_spec[:share_with_entity]
            return true if tool_spec[:public]
            
            # Check if user has explicit permission
            PluginPermission.exists?(
              plugin_id: tool_spec[:id],
              user_id: exec_user.id,
              permission_type: 'execute'
            )
          end
        end
      end
      
      def create_model_adapter(model_spec)
        case model_spec[:type]
        when 'huggingface'
          HuggingFaceAdapter.new(model_spec)
        when 'ollama'
          OllamaAdapter.new(model_spec)
        when 'openai'
          OpenAIAdapter.new(model_spec)
        when 'anthropic'
          AnthropicAdapter.new(model_spec)
        when 'custom_api'
          CustomAPIAdapter.new(model_spec)
        else
          raise "Unknown model type: #{model_spec[:type]}"
        end
      end
      
      def test_model_connection(model_spec)
        adapter = create_model_adapter(model_spec)
        
        begin
          response = adapter.test_connection
          {
            success: true,
            latency_ms: response[:latency_ms],
            model_info: response[:model_info]
          }
        rescue => e
          {
            success: false,
            error: "Connection failed: #{e.message}"
          }
        end
      end
      
      def check_forbidden_patterns(code)
        forbidden = []
        
        # File system access
        forbidden << "File system access" if code =~ /\b(File|Dir|IO)\./
        
        # Network access (unless explicitly allowed)
        forbidden << "Network access" if code =~ /\b(Net::|HTTP|RestClient|Faraday)\b/
        
        # Process execution
        forbidden << "Process execution" if code =~ /\b(system|exec|spawn|`)/
        
        # Dangerous eval
        forbidden << "Dynamic code execution" if code =~ /\b(eval|instance_eval|class_eval)\b/
        
        # Database access
        forbidden << "Direct database access" if code =~ /\b(ActiveRecord::Base\.connection|execute)\b/
        
        forbidden
      end
      
      def estimate_resource_usage(code)
        # Simple heuristics for resource estimation
        risk_score = 0
        
        # Loops
        risk_score += 2 if code =~ /\b(while|until)\b/
        risk_score += 1 if code =~ /\b(loop|times|each)\b/
        
        # Recursion
        risk_score += 3 if code =~ /def\s+(\w+).*\n.*\1/m
        
        # Large data structures
        risk_score += 2 if code =~ /\*\s*\d{4,}/
        
        {
          risk_score: risk_score,
          high_risk: risk_score > 5
        }
      end
      
      def has_method?(ast, method_name)
        # Walk AST to find method definition
        # This is simplified - real implementation would use proper AST traversal
        ast.to_s.include?("def #{method_name}")
      end
      
      def extract_metadata_from_code(code)
        metadata = {}
        
        # Extract from comments
        if match = code.match(/@name\s+(.+)/)
          metadata[:name] = match[1].strip
        end
        
        if match = code.match(/@capabilities\s+(.+)/)
          metadata[:capabilities] = match[1].split(',').map(&:strip)
        end
        
        if match = code.match(/@version\s+(.+)/)
          metadata[:version] = match[1].strip
        end
        
        metadata
      end
      
      def encrypt_api_key(api_key)
        return nil unless api_key
        
        Rails.application.message_verifier(:api_keys).generate(api_key)
      end
      
      def get_resource_limits(user)
        # Get user's subscription level
        subscription = user.subscription_level || 'free'
        
        case subscription
        when 'enterprise'
          {
            memory: '2GB',
            cpu_time: 5.minutes,
            api_calls: 10000,
            storage: '10GB'
          }
        when 'pro'
          {
            memory: '1GB',
            cpu_time: 2.minutes,
            api_calls: 1000,
            storage: '1GB'
          }
        else # free
          {
            memory: '256MB',
            cpu_time: 30.seconds,
            api_calls: 100,
            storage: '100MB'
          }
        end
      end
      
      def track_plugin_usage(plugin_id, usage)
        PluginUsage.create!(
          plugin_id: plugin_id,
          timestamp: Time.current,
          memory_mb: usage[:memory_mb],
          cpu_seconds: usage[:cpu_seconds],
          api_calls: usage[:api_calls],
          tokens_used: usage[:tokens_used]
        )
      rescue => e
        Rails.logger.error "Failed to track plugin usage: #{e.message}"
      end
      
      def get_system_plugins(type)
        case type
        when 'agent'
          [
            { id: 'planner', name: 'Planner Agent', capabilities: ['planning'] },
            { id: 'executor', name: 'Executor Agent', capabilities: ['execution'] },
            { id: 'monitor', name: 'Monitor Agent', capabilities: ['monitoring'] }
          ]
        when 'tool'
          ::Tools::ToolCatalog.instance.tools.map do |name, info|
            {
              id: name,
              name: info[:metadata][:name],
              description: info[:metadata][:description]
            }
          end
        else
          []
        end
      end
      
      def get_shared_plugins(user, type)
        # Get plugins shared in marketplace
        # TODO: Implement SharedPlugin model for marketplace features
        []
      end
      
      def default_resource_limits
        {
          memory: '256MB',
          cpu_time: 30.seconds,
          api_calls: 100,
          network_access: false
        }
      end
    end
  end
end
