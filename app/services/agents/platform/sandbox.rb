module Agents
  module Platform
    class Sandbox
      class SecurityError < StandardError; end
      class ResourceLimitError < StandardError; end
      
      attr_reader :name, :permissions, :resource_limits, :resource_usage
      
      def initialize(name:, permissions: [], resource_limits: {})
        @name = name
        @permissions = permissions
        @resource_limits = resource_limits
        @resource_usage = {
          memory_mb: 0,
          cpu_seconds: 0,
          api_calls: 0,
          tokens_used: 0,
          network_requests: 0
        }
        @start_time = nil
        @fiber = nil
        @context = {}
      end
      
      # Execute code in sandbox
      def execute(&block)
        @start_time = Time.current
        
        # Create isolated execution environment
        @fiber = Fiber.new do
          begin
            # Set resource limits
            apply_resource_limits
            
            # Create restricted binding
            sandbox_binding = create_sandbox_binding
            
            # Execute block with sandbox environment
            env = SandboxEnvironment.new(self, sandbox_binding)
            result = block.call(env)
            
            # Return result
            { success: true, result: result, usage: @resource_usage }
          rescue SecurityError => e
            { success: false, error: "Security violation: #{e.message}", usage: @resource_usage }
          rescue ResourceLimitError => e
            { success: false, error: "Resource limit exceeded: #{e.message}", usage: @resource_usage }
          rescue => e
            { success: false, error: "Execution error: #{e.message}", usage: @resource_usage }
          ensure
            cleanup
          end
        end
        
        # Run with timeout
        Timeout.timeout(resource_limits[:cpu_time] || 30) do
          @fiber.resume
        end
      rescue Timeout::Error
        raise ResourceLimitError, "CPU time limit exceeded"
      end
      
      # Check if method is allowed
      def allowed_method?(method_name)
        return false if FORBIDDEN_METHODS.include?(method_name.to_sym)
        return true if ALLOWED_METHODS.include?(method_name.to_sym)
        
        # Check permissions
        @permissions.any? do |perm|
          case perm
          when :file_read
            %i[read_file file_exists?].include?(method_name.to_sym)
          when :network
            %i[http_get http_post].include?(method_name.to_sym)
          when :database_read
            %i[query find_record].include?(method_name.to_sym)
          else
            false
          end
        end
      end
      
      # Track API call
      def track_api_call(service, tokens = 0)
        @resource_usage[:api_calls] += 1
        @resource_usage[:tokens_used] += tokens
        
        if @resource_usage[:api_calls] > (@resource_limits[:api_calls] || 100)
          raise ResourceLimitError, "API call limit exceeded"
        end
      end
      
      # Track memory usage
      def track_memory_usage
        # Get current memory usage (simplified)
        current_memory = `ps -o rss= -p #{Process.pid}`.to_i / 1024 # MB
        @resource_usage[:memory_mb] = [current_memory, @resource_usage[:memory_mb]].max
        
        limit = parse_memory_limit(@resource_limits[:memory] || '256MB')
        if @resource_usage[:memory_mb] > limit
          raise ResourceLimitError, "Memory limit exceeded: #{@resource_usage[:memory_mb]}MB > #{limit}MB"
        end
      end
      
      # Track network request
      def track_network_request(url)
        unless @permissions.include?(:network)
          raise SecurityError, "Network access not permitted"
        end
        
        @resource_usage[:network_requests] += 1
        
        # Validate URL
        uri = URI.parse(url)
        unless ALLOWED_DOMAINS.include?(uri.host) || @permissions.include?(:unrestricted_network)
          raise SecurityError, "Access to #{uri.host} not permitted"
        end
      end
      
      private
      
      FORBIDDEN_METHODS = %i[
        eval instance_eval class_eval module_eval
        system exec spawn ` fork
        require require_relative load
        File Dir IO Process
        send __send__ public_send
        const_set remove_const
        define_method define_singleton_method
        alias_method undef_method remove_method
        binding method instance_method
      ].freeze
      
      ALLOWED_METHODS = %i[
        puts print p
        Array Hash String Integer Float
        map select reject filter reduce
        each each_with_index
        nil? empty? present? blank?
        to_s to_i to_f to_h to_a
        + - * / % **
        == != < > <= >=
        && || !
        if else elsif unless case when
        begin rescue ensure
        catch throw
      ].freeze
      
      ALLOWED_DOMAINS = %w[
        api.openai.com
        api.anthropic.com
        api.cohere.ai
        huggingface.co
      ].freeze
      
      def apply_resource_limits
        # Set memory limit (simplified - real implementation would use cgroups)
        if @resource_limits[:memory]
          # This is a placeholder - actual memory limiting requires OS-level controls
          Thread.current[:memory_limit] = parse_memory_limit(@resource_limits[:memory])
        end
        
        # CPU tracking
        Thread.current[:cpu_start] = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
      end
      
      def create_sandbox_binding
        # Create a clean binding with limited access
        sandbox_module = Module.new do
          # Add safe methods
          def puts(*args)
            # Safe puts that doesn't leak information
            args.map(&:to_s).join(' ')
          end
          
          def get_data(key)
            # Safe data access through sandbox
            Thread.current[:sandbox].get_context_data(key)
          end
          
          def set_data(key, value)
            # Safe data storage through sandbox
            Thread.current[:sandbox].set_context_data(key, value)
          end
          
          def api_call(service, method, params = {})
            # Tracked API calls
            Thread.current[:sandbox].make_api_call(service, method, params)
          end
        end
        
        # Store sandbox reference
        Thread.current[:sandbox] = self
        
        # Return clean binding
        sandbox_module.instance_eval { binding }
      end
      
      def cleanup
        # Calculate CPU usage
        if Thread.current[:cpu_start]
          cpu_end = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
          @resource_usage[:cpu_seconds] = cpu_end - Thread.current[:cpu_start]
        end
        
        # Clear thread locals
        Thread.current[:sandbox] = nil
        Thread.current[:memory_limit] = nil
        Thread.current[:cpu_start] = nil
      end
      
      def parse_memory_limit(limit_str)
        case limit_str
        when /(\d+)GB?/i
          $1.to_i * 1024
        when /(\d+)MB?/i
          $1.to_i
        when /(\d+)KB?/i
          $1.to_i / 1024
        else
          256 # Default 256MB
        end
      end
      
      public
      
      # Safe API call method
      def make_api_call(service, method, params)
        track_api_call(service)
        
        # Route to appropriate service adapter
        case service
        when :openai
          make_openai_call(method, params)
        when :anthropic
          make_anthropic_call(method, params)
        when :tool
          make_tool_call(method, params)
        else
          raise SecurityError, "Unknown service: #{service}"
        end
      end
      
      # Context data access
      def get_context_data(key)
        @context[key]
      end
      
      def set_context_data(key, value)
        # Limit data size
        if value.to_s.length > 1_000_000 # 1MB limit
          raise ResourceLimitError, "Data too large"
        end
        
        @context[key] = value
      end
      
      private
      
      def make_openai_call(method, params)
        # Validate and proxy OpenAI calls
        case method
        when :complete
          # Track token usage
          estimated_tokens = (params[:prompt].to_s.length / 4) + (params[:max_tokens] || 100)
          track_api_call(:openai, estimated_tokens)
          
          # Make actual call through secure proxy
          SecureAPIProxy.openai_complete(params)
        else
          raise SecurityError, "Unknown OpenAI method: #{method}"
        end
      end
      
      def make_anthropic_call(method, params)
        case method
        when :complete
          estimated_tokens = (params[:prompt].to_s.length / 4) + (params[:max_tokens] || 100)
          track_api_call(:anthropic, estimated_tokens)
          
          SecureAPIProxy.anthropic_complete(params)
        else
          raise SecurityError, "Unknown Anthropic method: #{method}"
        end
      end
      
      def make_tool_call(tool_name, params)
        # Validate tool access
        unless @permissions.include?(:tools) || @permissions.include?("tool:#{tool_name}")
          raise SecurityError, "Tool access not permitted: #{tool_name}"
        end
        
        track_api_call(:tool)
        
        # Execute tool through catalog
        Tools::ToolCatalog.instance.execute_tool(
          tool_name,
          params,
          { sandbox: true, sandbox_id: @name }
        )
      end
    end
    
    # Environment provided to sandboxed code
    class SandboxEnvironment
      def initialize(sandbox, binding)
        @sandbox = sandbox
        @binding = binding
      end
      
      attr_accessor :context, :user, :entity
      
      def eval(code)
        # Track memory before eval
        @sandbox.track_memory_usage
        
        # Evaluate in restricted binding
        @binding.eval(code)
      end
      
      def call_method(method_name, *args, &block)
        unless @sandbox.allowed_method?(method_name)
          raise Sandbox::SecurityError, "Method not allowed: #{method_name}"
        end
        
        # Track memory
        @sandbox.track_memory_usage
        
        # Call method in binding context
        @binding.eval("method(#{method_name.inspect})").call(*args, &block)
      end
      
      def set_limits(limits)
        @sandbox.resource_limits.merge!(limits)
      end
      
      def resource_usage
        @sandbox.resource_usage
      end
    end
  end
end




