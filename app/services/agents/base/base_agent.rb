module Agents
  module Base
    class BaseAgent
      
      attr_reader :id, :role, :capabilities, :memory, :context, :state, :metrics
      attr_accessor :task_session
      
      def initialize(role:, capabilities: [], context: {}, task_session: nil)
        @id = SecureRandom.uuid
        @role = role
        @capabilities = capabilities
        @context = Agents::Communication::SharedContext.new(context)
        @memory = Agents::Memory::AgentMemory.new(agent_id: @id, role: @role)
        @task_session = task_session
        @state = :idle
        @metrics = { decisions: 0, actions: 0, collaborations: 0 }
        @logger = Rails.logger
        @ai_service = BedrockService.new
        
        # Initialize observability
        @decision_tracer = Agents::Observability::DecisionTracer.instance
        @performance_monitor = Agents::Observability::PerformanceMonitor.instance
        
        register_agent
      end
      
      # Core agent loop
      def run
        @state = :active
        
        while @state == :active
          begin
            # Perceive environment
            observations = perceive
            
            # Think and make decisions
            decisions = think(observations)
            
            # Act on decisions
            actions = act(decisions)
            
            # Learn from outcomes
            learn(actions)
            
            # Collaborate if needed
            collaborate_if_needed(decisions)
            
            # Check if we should continue
            @state = should_continue? ? :active : :complete
            
          rescue => e
            handle_error(e)
          end
          
          # Prevent tight loops
          sleep(0.1)
        end
        
        finalize
      end
      
      # Perceive the environment
      def perceive
        observations = {
          context: @context.read_all,
          messages: check_messages,
          task_state: @task_session&.current_state,
          resources: check_resources
        }
        
        @memory.store_short_term(:last_observations, observations)
        observations
      end
      
      # Think and reason about observations
      def think(observations)
        @metrics[:decisions] += 1
        
        # Start decision trace
        trace_id = @decision_tracer.start_trace(@id, :reasoning, {
          observations: observations,
          context: @context.read_all
        })
        
        start_time = Time.current
        
        begin
          # Build reasoning prompt
          prompt = build_reasoning_prompt(observations)
          
          @decision_tracer.add_reasoning(trace_id, :prompt_building, 
            "Built prompt from #{observations.size} observations")
          
          # Use AI for complex reasoning
          response = @ai_service.complete(
            messages: [
              { role: 'system', content: system_prompt },
              { role: 'user', content: prompt }
            ],
            temperature: 0.7,
            max_tokens: 1000
          )
          
          @decision_tracer.add_reasoning(trace_id, :ai_reasoning, 
            "AI provided reasoning", { response_length: response.length })
          
          decisions = parse_decisions(response)
          
          # Calculate confidence
          confidence = calculate_confidence(decisions)
          @decision_tracer.add_confidence(trace_id, :overall, confidence, 
            "Based on #{decisions.size} decisions")
          
          # Store reasoning trace
          @memory.store_short_term(:last_reasoning, {
            observations: observations,
            decisions: decisions,
            reasoning: response
          })
          
          # Complete trace
          @decision_tracer.complete_trace(trace_id, :success, decisions)
          
          # Record performance metrics
          duration = Time.current - start_time
          @performance_monitor.record_action(@id, :think, duration, true, {
            observation_count: observations.size,
            decision_count: decisions.size,
            confidence: confidence
          })
          
          decisions
        rescue => e
          # Complete trace with failure
          @decision_tracer.complete_trace(trace_id, :failure, { error: e.message })
          
          # Record failure metrics
          duration = Time.current - start_time
          @performance_monitor.record_action(@id, :think, duration, false, {
            error: e.class.name
          })
          
          raise
        end
      end
      
      # Execute actions based on decisions
      def act(decisions)
        @metrics[:actions] += 1
        actions_taken = []
        
        decisions.each do |decision|
          start_time = Time.current
          action_success = true
          
          begin
            case decision[:type]
            when :use_tool
              result = use_tool(decision[:tool], decision[:args])
              actions_taken << { type: :tool_use, tool: decision[:tool], result: result }
              
              # Track tool usage
              @performance_monitor.record_resource_usage(@id, :tool_calls, 1)
              
            when :send_message
              send_message(decision[:recipient], decision[:message])
              actions_taken << { type: :message_sent, recipient: decision[:recipient] }
              
              # Track collaboration
              @performance_monitor.record_collaboration(@id, decision[:recipient], 
                :message, :sent)
              
            when :update_context
              @context.write(decision[:key], decision[:value], @id)
              actions_taken << { type: :context_update, key: decision[:key] }
              
            when :request_help
              request_assistance(decision[:task])
              actions_taken << { type: :help_requested, task: decision[:task] }
              
              # Track collaboration request
              @performance_monitor.record_collaboration(@id, :broadcast, 
                :help_request, :sent)
            end
          rescue => e
            action_success = false
            actions_taken << { 
              type: decision[:type], 
              error: e.message, 
              failed: true 
            }
          ensure
            # Record action performance
            duration = Time.current - start_time
            @performance_monitor.record_action(@id, decision[:type], 
              duration, action_success)
          end
        end
        
        actions_taken
      end
      
      # Learn from action outcomes
      def learn(actions)
        return if actions.empty?
        
        # Evaluate outcomes
        outcomes = evaluate_outcomes(actions)
        
        # Update memory with successful patterns
        successful_patterns = outcomes.select { |o| o[:success] }
        if successful_patterns.any?
          @memory.store_long_term(:successful_patterns, successful_patterns)
        end
        
        # Learn from failures
        failed_patterns = outcomes.reject { |o| o[:success] }
        if failed_patterns.any?
          @memory.store_long_term(:failed_patterns, failed_patterns)
          
          # Trigger adaptation
          adapt_strategy(failed_patterns)
        end
      end
      
      # Collaborate with other agents
      def collaborate(other_agent_id, message_type, content)
        @metrics[:collaborations] += 1
        
        # Use MessageBroker to deliver message
        Agents::Communication::MessageBroker.instance.deliver(
          from: @id,
          to: other_agent_id,
          content: { 
            type: message_type, 
            data: content,
            task_session_id: @task_session&.id 
          }
        )
        
        # Track collaboration
        # TODO: Fix ObservabilityService integration
        # if defined?(ObservabilityService)
        #   ObservabilityService.instance.track_collaboration(
        #     [@id, other_agent_id], message_type, 'initiated'
        #   )
        # end
        
        # Return success
        { sent: true, to: other_agent_id, type: message_type }
      end
      
      # Handle incoming messages
      def handle_message(message)
        case message.message_type
        when 'help_request'
          assist_with_task(message)
        when 'insight'
          incorporate_insight(message)
        when 'coordination'
          coordinate_action(message)
        else
          @logger.warn "Unknown message type: #{message.message_type}"
        end
      end
      
      # Request assistance from other agents
      def request_assistance(task_description)
        # Find capable agents
        capable_agents = Agents::Communication::AgentRegistry.find_capable_agents(
          task_description[:required_capabilities]
        )
        
        # Send help request to most suitable agent
        if best_agent = select_best_agent(capable_agents, task_description)
          collaborate(best_agent.id, 'help_request', {
            task: task_description,
            context: @context.read_all,
            requester_role: @role
          })
        end
      end
      
      # Check resource availability
      def request_resources(resource_type, amount)
        return true unless @task_session # No restrictions without session
        
        resource_manager = ResourceManager.new(@task_session.user.entity)
        resource_manager.request_resources(@id, resource_type, amount)
      end
      
      # Graceful shutdown
      def shutdown
        @state = :shutting_down
        finalize
      end
      
      protected
      
      # Override in subclasses for role-specific prompts
      def system_prompt
        "You are an AI agent with role: #{@role}. You have capabilities: #{@capabilities.join(', ')}. 
        Make decisions based on observations and past experience. Be efficient and collaborative."
      end
      
      # Build reasoning prompt from observations
      def build_reasoning_prompt(observations)
        recent_memory = @memory.get_recent_memories(5)
        
        <<~PROMPT
          Current observations:
          #{observations.to_json}
          
          Recent memory:
          #{recent_memory.to_json}
          
          Task context:
          #{@task_session&.current_state&.to_json}
          
          What actions should I take? Respond with a JSON array of decisions.
          Each decision should have: type, description, and relevant parameters.
          
          Types: use_tool, send_message, update_context, request_help, wait
        PROMPT
      end
      
      # Parse AI response into decisions
      def parse_decisions(response)
        begin
          content = response.dig('choices', 0, 'message', 'content') || response
          
          # Extract JSON from response
          json_match = content.match(/\[.*\]/m)
          return [] unless json_match
          
          decisions = JSON.parse(json_match[0], symbolize_names: true)
          decisions.is_a?(Array) ? decisions : [decisions]
        rescue => e
          @logger.error "Failed to parse decisions: #{e.message}"
          []
        end
      end
      
      # Use a tool
      def use_tool(tool_name, args)
        return { error: 'No capabilities' } unless @capabilities.include?(tool_name)
        
        # Check resource cost
        tool_cost = estimate_tool_cost(tool_name)
        unless request_resources(:api_calls, tool_cost)
          return { error: 'Insufficient resources' }
        end
        
        # Execute tool with resilience
        resilience_options = {
          circuit_breaker: { 
            failure_threshold: 3,
            timeout: 30.seconds 
          },
          retry: { 
            max_attempts: 2,
            backoff: :exponential 
          },
          timeout: 60.seconds,
          fallback: ->(error) { 
            { error: "Tool execution failed: #{error.message}", fallback: true }
          }
        }
        
        # Use resilience manager if available
        if defined?(Agents::Resilience::ResilienceManager)
          Agents::Resilience::ResilienceManager.instance.execute("tool_#{tool_name}", resilience_options) do
            # Execute tool
            tool_catalog = ::Tools::ToolCatalog.instance
            tool_catalog.execute_tool(tool_name, args, {
              user: @task_session&.user,
              entity: @task_session&.user&.entity
            })
          end
        else
          # Direct execution without resilience
          tool_catalog = ::Tools::ToolCatalog.instance
          tool_catalog.execute_tool(tool_name, args, {
            user: @task_session&.user,
            entity: @task_session&.user&.entities&.first
          })
        end
      end
      
      # Send message to another agent
      def send_message(recipient_id, content)
        Agents::Communication::MessageBroker.deliver(
          from: @id,
          to: recipient_id,
          content: content
        )
      end
      
      # Check for new messages
      def check_messages
        Agents::Communication::MessageBroker.check_messages(@id)
      end
      
      # Evaluate action outcomes
      def evaluate_outcomes(actions)
        actions.map do |action|
          success = case action[:type]
          when :tool_use
            !action[:result][:error]
          when :message_sent
            true # Assume success unless we get delivery failure
          else
            true
          end
          
          {
            action: action,
            success: success,
            timestamp: Time.current
          }
        end
      end
      
      # Adapt strategy based on failures
      def adapt_strategy(failed_patterns)
        # Analyze failure patterns
        common_failures = analyze_failure_patterns(failed_patterns)
        
        # Update decision weights
        @memory.update_decision_weights(common_failures)
        
        # Request help if repeatedly failing
        if repeated_failures?(failed_patterns)
          request_assistance({
            task_type: 'failure_recovery',
            failures: failed_patterns,
            required_capabilities: ['problem_solving', @role]
          })
        end
      end
      
      # Should agent continue running?
      def should_continue?
        return false if @state == :shutting_down
        return false if @task_session && @task_session.reload.completed?
        
        # Check if we have pending work
        has_pending_messages? || has_pending_decisions?
      end
      
      # Finalize agent execution
      def finalize
        # Save memory to long-term storage
        @memory.persist!
        
        # Update metrics
        @task_session&.add_event('agent_completed', {
          agent_id: @id,
          role: @role,
          metrics: @metrics,
          final_state: @state
        })
        
        # Unregister from registry
        unregister_agent
      end
      
      # Error handling
      def handle_error(error)
        @logger.error "Agent #{@id} error: #{error.message}"
        @logger.error error.backtrace.join("\n")
        
        # Try to recover
        case error
        when Timeout::Error
          @state = :timeout
        when StandardError
          # Log and continue
          @memory.store_short_term(:last_error, {
            error: error.message,
            backtrace: error.backtrace,
            timestamp: Time.current
          })
        else
          # Serious error, shut down
          @state = :error
        end
      end
      
      private
      
      def register_agent
        Agents::Communication::AgentRegistry.register(self)
      end
      
      def unregister_agent
        Agents::Communication::AgentRegistry.unregister(@id)
      end
      
      def has_pending_messages?
        check_messages.any?
      end
      
      def has_pending_decisions?
        # Override in subclasses
        false
      end
      
      def select_best_agent(agents, task)
        # Simple selection - can be made more sophisticated
        agents.max_by { |agent| agent.capabilities & task[:required_capabilities] }
      end
      
      def estimate_tool_cost(tool_name)
        # Simple cost estimation - can be enhanced
        case tool_name
        when /ai_|generate_|analyze_/
          10 # High cost for AI tools
        when /get_|list_|read_/
          1  # Low cost for read operations
        else
          5  # Medium cost for others
        end
      end
      
      def analyze_failure_patterns(failures)
        # Group failures by type
        failures.group_by { |f| f[:action][:type] }
      end
      
      def repeated_failures?(failures)
        # Check if we have 3+ failures of same type in last 5 minutes
        recent_failures = failures.select { |f| f[:timestamp] > 5.minutes.ago }
        recent_failures.group_by { |f| f[:action][:type] }.any? { |_, group| group.size >= 3 }
      end
      
      def calculate_confidence(decisions)
        # Simple confidence calculation
        return 0.5 if decisions.empty?
        
        # Higher confidence if decisions align with past successful patterns
        successful_patterns = @memory.get_long_term(:successful_patterns) || []
        matching_patterns = decisions.count do |decision|
          successful_patterns.any? { |pattern| pattern[:action][:type] == decision[:type] }
        end
        
        base_confidence = 0.5
        pattern_bonus = (matching_patterns.to_f / decisions.size) * 0.3
        experience_bonus = [@metrics[:decisions] / 100.0, 0.2].min
        
        base_confidence + pattern_bonus + experience_bonus
      end
      
      def collaborate_if_needed(decisions)
        # Check if any decisions suggest collaboration would help
        complex_decisions = decisions.select { |d| d[:complexity] == :high }
        
        if complex_decisions.any?
          # Find agents with complementary skills
          needed_skills = complex_decisions.flat_map { |d| d[:required_skills] }.uniq
          complementary_agents = Agents::Communication::AgentRegistry.find_by_capabilities(
            needed_skills - @capabilities
          )
          
          # Initiate collaboration
          complementary_agents.each do |agent|
            collaborate(agent.id, 'coordination', {
              decisions: complex_decisions,
              requesting_assistance: true
            })
          end
        end
      end
      
      def assist_with_task(message)
        # Help another agent with their task
        task = message.content[:task]
        
        # Check if we can help
        if can_help_with?(task)
          # Provide assistance
          assistance = generate_assistance(task)
          
          # Send response
          collaborate(message.sender_id, 'assistance_response', {
            original_request: task,
            assistance: assistance,
            confidence: calculate_assistance_confidence(task)
          })
        end
      end
      
      def can_help_with?(task)
        required = task[:required_capabilities] || []
        (required & @capabilities).any?
      end
      
      def generate_assistance(task)
        # Use our experience to help
        relevant_patterns = @memory.find_relevant_patterns(task)
        
        {
          suggested_approach: extract_approach(relevant_patterns),
          relevant_tools: suggest_tools(task),
          potential_issues: identify_potential_issues(task),
          examples: relevant_patterns.take(3)
        }
      end
      
      def extract_approach(patterns)
        # Extract common successful approaches
        patterns.map { |p| p[:approach] }.compact.first
      end
      
      def suggest_tools(task)
        # Suggest tools based on task type
        Tools::ToolCatalog.instance.categories.select do |category|
          task[:description]&.include?(category.to_s)
        end
      end
      
      def identify_potential_issues(task)
        # Check against known failure patterns
        failed_patterns = @memory.get_long_term(:failed_patterns) || []
        failed_patterns.select { |p| similar_task?(p[:task], task) }
      end
      
      def similar_task?(task1, task2)
        # Simple similarity check
        return false unless task1 && task2
        
        (task1[:type] == task2[:type]) ||
        (task1[:required_capabilities] & task2[:required_capabilities]).any?
      end
      
      def calculate_assistance_confidence(task)
        # Calculate how confident we are in our assistance
        relevant_experience = @memory.count_relevant_experiences(task)
        
        case relevant_experience
        when 0..2 then 0.3
        when 3..10 then 0.6
        else 0.9
        end
      end
      
      def incorporate_insight(message)
        insight = message.content
        
        # Store insight in memory
        @memory.store_long_term(:insights, {
          from: message.sender_id,
          insight: insight,
          timestamp: Time.current
        })
        
        # Update our decision making based on insight
        if insight[:type] == 'pattern'
          @memory.add_pattern(insight[:pattern])
        end
      end
      
      def coordinate_action(message)
        coordination_request = message.content
        
        # Synchronize with requesting agent
        if coordination_request[:requesting_assistance]
          assist_with_task(message)
        else
          # Coordinate joint action
          synchronize_actions(coordination_request)
        end
      end
      
      def synchronize_actions(request)
        # Implement action synchronization
        # This would coordinate timing and sequencing with other agents
      end
      
      def check_resources
        return {} unless @task_session
        
        resource_manager = ResourceManager.new(@task_session.user.entity)
        {
          api_calls_remaining: resource_manager.remaining_budget(:api_calls),
          compute_time_remaining: resource_manager.remaining_budget(:compute_time)
        }
      end
    end
  end
end
