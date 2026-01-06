# frozen_string_literal: true

module Amos
  # RoutingIntelligence - Decides how AMOS should handle each request
  #
  # AMOS can:
  # 1. Handle directly (with tools)
  # 2. Delegate to a specialized agent
  # 3. Create a support ticket
  # 4. Escalate to a human
  # 5. Decline gracefully (with alternatives)
  #
  class RoutingIntelligence
    attr_reader :entity, :user, :capabilities, :awareness

    # Request categories
    CATEGORIES = {
      simple_question: {
        patterns: ['what is', 'how do i', 'can you explain', 'tell me about'],
        action: :direct_answer
      },
      search_request: {
        patterns: ['find', 'search', 'look up', 'show me'],
        action: :tool_call
      },
      create_request: {
        patterns: ['create', 'add', 'make', 'generate', 'write'],
        action: :determine_complexity
      },
      action_request: {
        patterns: ['send', 'schedule', 'update', 'delete', 'change'],
        action: :tool_call
      },
      analysis_request: {
        patterns: ['analyze', 'report', 'compare', 'forecast', 'predict'],
        action: :agent_delegation
      },
      problem_report: {
        patterns: ['bug', 'error', 'broken', 'not working', 'issue', 'problem', 'wrong'],
        action: :create_ticket
      },
      sensitive_request: {
        patterns: ['delete all', 'remove all', 'billing', 'payment', 'password', 'security'],
        action: :human_escalation
      }
    }.freeze

    def initialize(entity, user)
      @entity = entity
      @user = user
      @capabilities = CapabilityRegistry.new(entity)
      @awareness = PlatformAwareness.new(entity)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MAIN ROUTING DECISION
    # ═══════════════════════════════════════════════════════════════════════════

    def route(user_message)
      message_lower = user_message.downcase

      # Step 1: Check for explicit patterns
      category = detect_category(message_lower)

      # Step 2: Determine action based on category
      decision = case category[:action]
                 when :direct_answer
                   { action: :answer_directly, reason: 'Simple question/chat' }

                 when :tool_call
                   tool = find_matching_tool(message_lower)
                   if tool
                     { action: :use_tool, tool: tool, reason: "Tool available: #{tool}" }
                   else
                     { action: :answer_directly, reason: 'No specific tool needed' }
                   end

                 when :determine_complexity
                   route_by_complexity(message_lower)

                 when :agent_delegation
                   agent = find_best_agent(message_lower)
                   if agent
                     { action: :delegate_to_agent, agent: agent, reason: "Specialized work for #{agent[:name]}" }
                   else
                     { action: :answer_directly, reason: 'No specialized agent available' }
                   end

                 when :create_ticket
                   { action: :create_ticket, reason: 'User reporting an issue' }

                 when :human_escalation
                   { action: :escalate_to_human, reason: 'Sensitive/critical request' }

                 else
                   { action: :answer_directly, reason: 'Default handling' }
                 end

      # Step 3: Check for limitations
      limitation = check_limitations(message_lower)
      if limitation
        decision = {
          action: :decline_gracefully,
          limitation: limitation,
          reason: 'Capability not available'
        }
      end

      decision.merge(
        original_message: user_message,
        category: category[:name],
        confidence: calculate_confidence(decision)
      )
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # DETECTION
    # ═══════════════════════════════════════════════════════════════════════════

    def detect_category(message)
      CATEGORIES.each do |name, config|
        if config[:patterns].any? { |pattern| message.include?(pattern) }
          return { name: name, action: config[:action] }
        end
      end

      { name: :general, action: :direct_answer }
    end

    def find_matching_tool(message)
      capabilities.direct_capabilities.each do |key, cap|
        # Check if any example matches
        if cap[:examples].any? { |ex| message.include?(ex.downcase.split.first(3).join(' ')) }
          return key.to_s
        end

        # Check capability name
        if message.include?(cap[:name].downcase)
          return key.to_s
        end
      end

      nil
    end

    def find_best_agent(message)
      capabilities.agent_for_task(message)
    end

    def check_limitations(message)
      capabilities.limitations.each do |limit|
        if message.include?(limit[:capability].downcase.split.first(2).join(' '))
          return limit
        end
      end

      nil
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # COMPLEXITY ROUTING
    # ═══════════════════════════════════════════════════════════════════════════

    def route_by_complexity(message)
      # Simple creation requests AMOS can handle
      simple_keywords = ['email', 'contact', 'reminder', 'task', 'note']
      if simple_keywords.any? { |k| message.include?(k) }
        tool = find_matching_tool(message)
        return { action: :use_tool, tool: tool, reason: 'Simple creation task' } if tool
      end

      # Module creation always goes to Platform Factory
      module_keywords = ['module', 'inventory', 'custom software', 'build me a', 'build an', 'design a system', 'tracking system']
      if module_keywords.any? { |k| message.include?(k) }
        agent = find_best_agent(message)
        if agent
          return { action: :delegate_to_agent, agent: agent, reason: 'Module creation needs Platform Factory' }
        end
      end

      # Complex creation needs an agent
      complex_keywords = ['campaign', 'report', 'analysis', 'strategy', 'content', 'article', 'blog']
      if complex_keywords.any? { |k| message.include?(k) }
        agent = find_best_agent(message)
        if agent
          return { action: :delegate_to_agent, agent: agent, reason: 'Complex creation needs specialist' }
        end
      end

      { action: :answer_directly, reason: 'Will determine complexity during conversation' }
    end

    def calculate_confidence(decision)
      case decision[:action]
      when :use_tool then 0.9
      when :delegate_to_agent then 0.85
      when :create_ticket then 0.95
      when :escalate_to_human then 0.95
      when :decline_gracefully then 1.0
      else 0.7
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # RESPONSE GENERATION
    # ═══════════════════════════════════════════════════════════════════════════

    def routing_context_for_prompt(decision)
      context = []

      case decision[:action]
      when :delegate_to_agent
        agent = decision[:agent]
        context << "You should delegate this to the #{agent[:name]}."
        context << "This agent specializes in: #{agent[:specializations].join(', ')}"
        context << "Use the delegate_to_agent tool with agent_id: #{agent[:id]}"

      when :use_tool
        context << "You should use the #{decision[:tool]} tool to handle this."

      when :create_ticket
        context << "This sounds like a bug report or issue."
        context << "Use the create_support_ticket tool to capture it."
        context << "Our Evolution Engine will investigate and potentially auto-fix it."

      when :escalate_to_human
        context << "This request requires human approval or is too sensitive for autonomous handling."
        context << "Politely explain that you'll need to connect them with a human."

      when :decline_gracefully
        limit = decision[:limitation]
        context << "This capability (#{limit[:capability]}) is not available."
        context << "Explain this honestly and offer the alternative: #{limit[:alternative]}"
      end

      context.join("\n")
    end
  end
end

