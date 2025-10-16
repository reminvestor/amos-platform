module Agents
  module Tools
    class ToolManager
      include Singleton

      def initialize
        @tool_permissions = Concurrent::Hash.new
        @tool_limits = Concurrent::Hash.new
        @tool_usage = Concurrent::Hash.new { |h, k| h[k] = Concurrent::Hash.new(0) }
        @shared_tools = Concurrent::Array.new
        @exclusive_tools = Concurrent::Hash.new
        @tool_pools = Concurrent::Hash.new

        load_default_configuration
      end

      # Register tool permissions for an agent
      def grant_tool_access(agent_id, tool_names, options = {})
        permissions = {
          tools: Array(tool_names),
          granted_at: Time.current,
          expires_at: options[:expires_at],
          usage_limit: options[:usage_limit],
          rate_limit: options[:rate_limit],
          priority: options[:priority] || :normal,
          conditions: options[:conditions] || {}
        }

        @tool_permissions[agent_id] = permissions

        Rails.logger.info "Granted tool access to agent #{agent_id}: #{tool_names.join(', ')}"
      end

      # Revoke tool access
      def revoke_tool_access(agent_id, tool_names = nil)
        if tool_names.nil?
          @tool_permissions.delete(agent_id)
        else
          permissions = @tool_permissions[agent_id]
          return unless permissions

          permissions[:tools] -= Array(tool_names)
          @tool_permissions[agent_id] = permissions if permissions[:tools].any?
        end
      end

      # Check if agent can use a tool
      def can_use_tool?(agent_id, tool_name, context = {})
        # Check basic permissions
        return false unless has_permission?(agent_id, tool_name)

        # Check expiration
        return false if permission_expired?(agent_id)

        # Check usage limits
        return false if usage_limit_exceeded?(agent_id, tool_name)

        # Check rate limits
        return false if rate_limit_exceeded?(agent_id, tool_name)

        # Check conditions
        return false unless conditions_met?(agent_id, tool_name, context)

        # Check if tool is available (not exclusively locked)
        return false if tool_exclusively_locked?(tool_name, agent_id)

        # Check pool availability for pooled tools
        return false unless pool_available?(tool_name)

        true
      end

      # Request tool usage
      def request_tool_use(agent_id, tool_name, context = {})
        unless can_use_tool?(agent_id, tool_name, context)
          return {
            granted: false,
            reason: get_denial_reason(agent_id, tool_name, context)
          }
        end

        # Try to acquire from pool if applicable
        if pooled_tool?(tool_name)
          token = acquire_from_pool(tool_name, agent_id)
          return { granted: false, reason: "Pool exhausted" } unless token

          return {
            granted: true,
            token: token,
            release_required: true
          }
        end

        # Record usage
        record_tool_usage(agent_id, tool_name)

        {
          granted: true,
          usage_count: @tool_usage[agent_id][tool_name]
        }
      end

      # Release tool after use
      def release_tool(agent_id, tool_name, token = nil)
        if token && pooled_tool?(tool_name)
          release_to_pool(tool_name, token)
        end

        # Could track active usage duration here
      end

      # Share a tool between agents
      def share_tool(from_agent_id, to_agent_id, tool_name, options = {})
        # Verify the sharing agent has the tool
        unless has_permission?(from_agent_id, tool_name)
          return { success: false, error: "Agent does not have tool access" }
        end

        # Check if tool is shareable
        unless tool_shareable?(tool_name)
          return { success: false, error: "Tool is not shareable" }
        end

        # Create shared access
        shared_access = {
          from: from_agent_id,
          to: to_agent_id,
          tool: tool_name,
          granted_at: Time.current,
          expires_at: options[:duration] ? Time.current + options[:duration] : nil,
          conditions: options[:conditions] || {}
        }

        @shared_tools << shared_access

        # Grant temporary access
        grant_tool_access(to_agent_id, tool_name, {
          expires_at: shared_access[:expires_at],
          usage_limit: options[:usage_limit]
        })

        { success: true, shared_access: shared_access }
      end

      # Set tool limits
      def set_tool_limits(tool_name, limits = {})
        @tool_limits[tool_name] = {
          max_concurrent_users: limits[:max_concurrent] || Float::INFINITY,
          rate_limit_per_minute: limits[:rate_per_minute] || Float::INFINITY,
          daily_usage_limit: limits[:daily_limit] || Float::INFINITY,
          cost_per_use: limits[:cost] || 0,
          exclusive_to: limits[:exclusive_to],
          shareable: limits[:shareable] != false,
          requires_approval: limits[:requires_approval] || false
        }
      end

      # Create a tool pool for resource-constrained tools
      def create_tool_pool(tool_name, pool_size)
        @tool_pools[tool_name] = ToolPool.new(tool_name, pool_size)
      end

      # Get tool usage statistics
      def get_usage_stats(agent_id = nil)
        if agent_id
          {
            agent_id: agent_id,
            permissions: @tool_permissions[agent_id],
            usage: @tool_usage[agent_id].to_h,
            active_shares: active_shares_for_agent(agent_id)
          }
        else
          {
            total_agents: @tool_permissions.size,
            total_usage: aggregate_usage,
            popular_tools: popular_tools,
            sharing_stats: sharing_statistics
          }
        end
      end

      # Configure tool for exclusive use
      def set_exclusive_tool(tool_name, agent_id, duration = nil)
        @exclusive_tools[tool_name] = {
          agent_id: agent_id,
          locked_at: Time.current,
          expires_at: duration ? Time.current + duration : nil
        }
      end

      # Release exclusive tool
      def release_exclusive_tool(tool_name)
        @exclusive_tools.delete(tool_name)
      end

      private

      def load_default_configuration
        # Load from configuration file or database
        default_tools = {
          # Basic tools available to all agents
          basic: %w[get_data get_schema list_connections],

          # Specialized tools requiring permission
          specialized: %w[create_object update_object delete_object],

          # Premium tools with usage limits
          premium: %w[generate_ai_landing_page create_dynamic_visualization],

          # Dangerous tools requiring special permission
          dangerous: %w[execute_sql direct_database_access]
        }

        # Set default limits
        default_tools[:premium].each do |tool|
          set_tool_limits(tool, {
            daily_limit: 100,
            rate_per_minute: 5,
            cost: 0.1
          })
        end

        default_tools[:dangerous].each do |tool|
          set_tool_limits(tool, {
            requires_approval: true,
            max_concurrent: 1
          })
        end
      end

      def has_permission?(agent_id, tool_name)
        permissions = @tool_permissions[agent_id]
        return false unless permissions

        permissions[:tools].include?(tool_name)
      end

      def permission_expired?(agent_id)
        permissions = @tool_permissions[agent_id]
        return false unless permissions

        expires_at = permissions[:expires_at]
        expires_at && Time.current > expires_at
      end

      def usage_limit_exceeded?(agent_id, tool_name)
        permissions = @tool_permissions[agent_id]
        return false unless permissions

        limit = permissions[:usage_limit]
        return false unless limit

        @tool_usage[agent_id][tool_name] >= limit
      end

      def rate_limit_exceeded?(agent_id, tool_name)
        # Check both agent-specific and tool-specific rate limits
        agent_rate_limit = @tool_permissions[agent_id]&.dig(:rate_limit)
        tool_rate_limit = @tool_limits[tool_name]&.dig(:rate_limit_per_minute)

        # Check agent rate limit
        if agent_rate_limit
          recent_uses = count_recent_uses(agent_id, tool_name, 1.minute)
          return true if recent_uses >= agent_rate_limit
        end

        # Check tool rate limit
        if tool_rate_limit
          total_recent_uses = count_total_recent_uses(tool_name, 1.minute)
          return true if total_recent_uses >= tool_rate_limit
        end

        false
      end

      def conditions_met?(agent_id, tool_name, context)
        permissions = @tool_permissions[agent_id]
        return true unless permissions

        conditions = permissions[:conditions]
        return true if conditions.empty?

        # Evaluate conditions
        conditions.all? do |key, value|
          case key
          when :time_of_day
            current_hour = Time.current.hour
            value[:from] <= current_hour && current_hour <= value[:to]
          when :context_required
            context[value].present?
          when :approval_required
            context[:approval_token].present?
          else
            true
          end
        end
      end

      def tool_exclusively_locked?(tool_name, agent_id)
        exclusive = @exclusive_tools[tool_name]
        return false unless exclusive

        # Check if lock expired
        if exclusive[:expires_at] && Time.current > exclusive[:expires_at]
          @exclusive_tools.delete(tool_name)
          return false
        end

        # Tool is locked by another agent
        exclusive[:agent_id] != agent_id
      end

      def pooled_tool?(tool_name)
        @tool_pools.key?(tool_name)
      end

      def pool_available?(tool_name)
        pool = @tool_pools[tool_name]
        return true unless pool

        pool.available?
      end

      def acquire_from_pool(tool_name, agent_id)
        pool = @tool_pools[tool_name]
        return nil unless pool

        pool.acquire(agent_id)
      end

      def release_to_pool(tool_name, token)
        pool = @tool_pools[tool_name]
        return unless pool

        pool.release(token)
      end

      def tool_shareable?(tool_name)
        limits = @tool_limits[tool_name]
        return true unless limits

        limits[:shareable]
      end

      def record_tool_usage(agent_id, tool_name)
        @tool_usage[agent_id][tool_name] += 1

        # Record timestamp for rate limiting
        key = "tool_usage:#{agent_id}:#{tool_name}:#{Time.current.to_i}"
        ($redis || Redis.new).setex(key, 300, 1) # Keep for 5 minutes

        # Emit usage event
        ActiveSupport::Notifications.instrument("agent.tool_used", {
          agent_id: agent_id,
          tool_name: tool_name,
          usage_count: @tool_usage[agent_id][tool_name]
        })
      end

      def count_recent_uses(agent_id, tool_name, duration)
        pattern = "tool_usage:#{agent_id}:#{tool_name}:*"
        keys = ($redis || Redis.new).keys(pattern)

        cutoff = Time.current - duration
        keys.count do |key|
          timestamp = key.split(":").last.to_i
          Time.at(timestamp) > cutoff
        end
      end

      def count_total_recent_uses(tool_name, duration)
        pattern = "tool_usage:*:#{tool_name}:*"
        keys = ($redis || Redis.new).keys(pattern)

        cutoff = Time.current - duration
        keys.count do |key|
          timestamp = key.split(":").last.to_i
          Time.at(timestamp) > cutoff
        end
      end

      def get_denial_reason(agent_id, tool_name, context)
        return "No permission granted" unless has_permission?(agent_id, tool_name)
        return "Permission expired" if permission_expired?(agent_id)
        return "Usage limit exceeded" if usage_limit_exceeded?(agent_id, tool_name)
        return "Rate limit exceeded" if rate_limit_exceeded?(agent_id, tool_name)
        return "Conditions not met" unless conditions_met?(agent_id, tool_name, context)
        return "Tool exclusively locked" if tool_exclusively_locked?(tool_name, agent_id)
        return "Pool exhausted" unless pool_available?(tool_name)

        "Unknown reason"
      end

      def active_shares_for_agent(agent_id)
        @shared_tools.select do |share|
          (share[:from] == agent_id || share[:to] == agent_id) &&
          (share[:expires_at].nil? || share[:expires_at] > Time.current)
        end
      end

      def aggregate_usage
        total = Hash.new(0)

        @tool_usage.each_value do |agent_usage|
          agent_usage.each do |tool, count|
            total[tool] += count
          end
        end

        total
      end

      def popular_tools
        aggregate_usage
          .sort_by { |_, count| -count }
          .first(10)
          .to_h
      end

      def sharing_statistics
        {
          total_shares: @shared_tools.size,
          active_shares: @shared_tools.count { |s| s[:expires_at].nil? || s[:expires_at] > Time.current },
          most_shared: @shared_tools.group_by { |s| s[:tool] }.transform_values(&:count).max_by { |_, v| v }
        }
      end
    end

    # Tool pool for managing limited resources
    class ToolPool
      def initialize(tool_name, size)
        @tool_name = tool_name
        @size = size
        @available = Concurrent::Array.new((1..size).map { |i| "#{tool_name}_token_#{i}" })
        @in_use = Concurrent::Hash.new
      end

      def available?
        !@available.empty?
      end

      def acquire(agent_id)
        token = @available.shift
        return nil unless token

        @in_use[token] = {
          agent_id: agent_id,
          acquired_at: Time.current
        }

        token
      end

      def release(token)
        usage = @in_use.delete(token)
        return unless usage

        @available << token

        # Log usage duration
        duration = Time.current - usage[:acquired_at]
        Rails.logger.info "Tool pool #{@tool_name}: Token released after #{duration.round(2)}s by agent #{usage[:agent_id]}"
      end

      def status
        {
          total: @size,
          available: @available.size,
          in_use: @in_use.size,
          utilization: (@in_use.size.to_f / @size * 100).round(2)
        }
      end
    end
  end
end
