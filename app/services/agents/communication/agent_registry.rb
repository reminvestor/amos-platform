module Agents
  module Communication
    class AgentRegistry
      include Singleton
      
      def initialize
        @agents = {}
        @agents_by_role = {}
        @agents_by_capability = {}
        @mutex = Mutex.new
        @redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/1')
      end
      
      # Register an agent
      def register(agent)
        @mutex.synchronize do
          @agents[agent.id] = {
            agent: agent,
            registered_at: Time.current,
            status: :active
          }
          
          # Index by role
          @agents_by_role[agent.role] ||= []
          @agents_by_role[agent.role] << agent.id
          
          # Index by capabilities
          agent.capabilities.each do |capability|
            @agents_by_capability[capability] ||= []
            @agents_by_capability[capability] << agent.id
          end
        end
        
        # Publish registration event
        publish_event(:agent_registered, {
          agent_id: agent.id,
          role: agent.role,
          capabilities: agent.capabilities
        })
        
        Rails.logger.info "Agent registered: #{agent.id} (#{agent.role})"
      end
      
      # Unregister an agent
      def unregister(agent_id)
        @mutex.synchronize do
          if agent_info = @agents[agent_id]
            agent = agent_info[:agent]
            
            # Remove from role index
            if @agents_by_role[agent.role]
              @agents_by_role[agent.role].delete(agent_id)
              @agents_by_role.delete(agent.role) if @agents_by_role[agent.role].empty?
            end
            
            # Remove from capability index
            agent.capabilities.each do |capability|
              if @agents_by_capability[capability]
                @agents_by_capability[capability].delete(agent_id)
                @agents_by_capability.delete(capability) if @agents_by_capability[capability].empty?
              end
            end
            
            # Remove from main registry
            @agents.delete(agent_id)
          end
        end
        
        # Publish unregistration event
        publish_event(:agent_unregistered, { agent_id: agent_id })
        
        Rails.logger.info "Agent unregistered: #{agent_id}"
      end
      
      # Find agents by capability
      def find_by_capabilities(capabilities)
        agent_ids = @mutex.synchronize do
          capabilities.flat_map do |capability|
            @agents_by_capability[capability] || []
          end.uniq
        end
        
        agent_ids.map { |id| get_agent(id) }.compact
      end
      
      # Find agents by role
      def find_by_role(role)
        agent_ids = @mutex.synchronize do
          @agents_by_role[role] || []
        end
        
        agent_ids.map { |id| get_agent(id) }.compact
      end
      
      # Find capable agents for a task
      def find_capable_agents(required_capabilities)
        return [] if required_capabilities.nil? || required_capabilities.empty?
        
        # Find agents that have ALL required capabilities
        agent_ids = @mutex.synchronize do
          @agents.select do |agent_id, info|
            agent = info[:agent]
            info[:status] == :active &&
              (required_capabilities - agent.capabilities).empty?
          end.keys
        end
        
        agent_ids.map { |id| get_agent(id) }.compact
      end
      
      # Get a specific agent
      def get_agent(agent_id)
        @mutex.synchronize do
          @agents[agent_id]&.dig(:agent)
        end
      end
      
      # Get all active agents
      def active_agents
        @mutex.synchronize do
          @agents.select { |_, info| info[:status] == :active }
                 .map { |_, info| info[:agent] }
        end
      end
      
      # Update agent status
      def update_status(agent_id, status)
        @mutex.synchronize do
          if @agents[agent_id]
            @agents[agent_id][:status] = status
            @agents[agent_id][:status_updated_at] = Time.current
          end
        end
        
        publish_event(:agent_status_changed, {
          agent_id: agent_id,
          status: status
        })
      end
      
      # Get agent statistics
      def statistics
        @mutex.synchronize do
          {
            total_agents: @agents.size,
            active_agents: @agents.count { |_, info| info[:status] == :active },
            agents_by_role: @agents_by_role.transform_values(&:size),
            agents_by_capability: @agents_by_capability.transform_values(&:size),
            average_uptime: calculate_average_uptime
          }
        end
      end
      
      # Find best agent for a task
      def find_best_agent_for_task(task_description)
        required_capabilities = task_description[:required_capabilities] || []
        preferred_role = task_description[:preferred_role]
        
        candidates = find_capable_agents(required_capabilities)
        
        # Filter by preferred role if specified
        if preferred_role
          role_candidates = candidates.select { |agent| agent.role == preferred_role }
          candidates = role_candidates if role_candidates.any?
        end
        
        # Score candidates
        scored_candidates = candidates.map do |agent|
          score = calculate_agent_score(agent, task_description)
          { agent: agent, score: score }
        end
        
        # Return best candidate
        best = scored_candidates.max_by { |c| c[:score] }
        best&.dig(:agent)
      end
      
      # Spawn a new agent
      def spawn_agent(role, context = {})
        agent_class = case role
        when :planner
          Agents::Specialized::PlannerAgent
        when :executor
          Agents::Specialized::ExecutorAgent
        when :monitor
          Agents::Specialized::MonitorAgent
        when :guard
          Agents::Specialized::GuardAgent
        when :analyst
          Agents::Specialized::AnalystAgent
        else
          raise "Unknown agent role: #{role}"
        end
        
        agent = agent_class.new(
          task_session: context[:task_session],
          initial_context: context
        )
        
        # Start agent in background
        Thread.new do
          begin
            agent.run
          rescue => e
            Rails.logger.error "Agent #{agent.id} crashed: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
            update_status(agent.id, :crashed)
          end
        end
        
        agent
      end
      
      # Broadcast message to all agents
      def broadcast(message_type, content, sender_id = nil)
        active_agents.each do |agent|
          next if agent.id == sender_id
          
          MessageBroker.deliver(
            from: sender_id || 'system',
            to: agent.id,
            content: {
              type: message_type,
              data: content
            }
          )
        end
      end
      
      # Health check for all agents
      def health_check
        @mutex.synchronize do
          @agents.map do |agent_id, info|
            agent = info[:agent]
            uptime = Time.current - info[:registered_at]
            
            {
              agent_id: agent_id,
              role: agent.role,
              status: info[:status],
              uptime_seconds: uptime,
              metrics: agent.metrics
            }
          end
        end
      end
      
      # Clean up inactive agents
      def cleanup_inactive(inactive_threshold = 5.minutes)
        inactive_agents = @mutex.synchronize do
          @agents.select do |_, info|
            info[:status] == :inactive &&
              info[:status_updated_at] &&
              info[:status_updated_at] < inactive_threshold.ago
          end.keys
        end
        
        inactive_agents.each { |agent_id| unregister(agent_id) }
        
        Rails.logger.info "Cleaned up #{inactive_agents.size} inactive agents"
      end
      
      private
      
      def calculate_average_uptime
        uptimes = @agents.map do |_, info|
          Time.current - info[:registered_at]
        end
        
        return 0 if uptimes.empty?
        
        uptimes.sum / uptimes.size
      end
      
      def calculate_agent_score(agent, task_description)
        score = 0.0
        
        # Base score for having required capabilities
        score += 1.0
        
        # Bonus for matching preferred role
        if task_description[:preferred_role] == agent.role
          score += 0.5
        end
        
        # Bonus for additional relevant capabilities
        extra_capabilities = agent.capabilities - (task_description[:required_capabilities] || [])
        score += extra_capabilities.size * 0.1
        
        # Consider agent metrics
        if agent.metrics[:success_rate]
          score += agent.metrics[:success_rate] * 0.3
        end
        
        # Consider agent load (prefer less busy agents)
        if agent.respond_to?(:current_load)
          load_factor = 1.0 - (agent.current_load / 10.0)
          score *= [load_factor, 0.5].max
        end
        
        score
      end
      
      def publish_event(event_type, data)
        event = {
          type: event_type,
          data: data,
          timestamp: Time.current
        }
        
        @redis.publish('agent_registry:events', event.to_json)
      rescue => e
        Rails.logger.error "Failed to publish registry event: #{e.message}"
      end
      
      class << self
        # Convenience methods that delegate to instance
        def register(agent)
          instance.register(agent)
        end
        
        def unregister(agent_id)
          instance.unregister(agent_id)
        end
        
        def find_by_capabilities(capabilities)
          instance.find_by_capabilities(capabilities)
        end
        
        def find_capable_agents(required_capabilities)
          instance.find_capable_agents(required_capabilities)
        end
        
        def find_best_agent_for_task(task_description)
          instance.find_best_agent_for_task(task_description)
        end
        
        def spawn_agent(role, context = {})
          instance.spawn_agent(role, context)
        end
        
        def get_agent(agent_id)
          instance.get_agent(agent_id)
        end
        
        def active_agents
          instance.active_agents
        end
        
        def broadcast(message_type, content, sender_id = nil)
          instance.broadcast(message_type, content, sender_id)
        end
      end
    end
  end
end




