# frozen_string_literal: true

module Amos
  # ScoutIntegration - Bridges the AMOS Orchestrator with Scout
  #
  # This module provides integration points for Scout to leverage:
  # - Platform awareness (health, tickets, PRs)
  # - Routing intelligence (what to do with requests)
  # - Capability registry (what's available)
  # - Dynamic context injection
  #
  # Usage:
  #   integration = Amos::ScoutIntegration.new(entity: entity, user: user)
  #   context = integration.get_context_injection
  #   routing = integration.get_routing_hint(user_message)
  #
  class ScoutIntegration
    attr_reader :entity, :user, :orchestrator

    def initialize(entity:, user:, conversation: nil)
      @entity = entity
      @user = user
      @orchestrator = Orchestrator.new(entity: entity, user: user, conversation: conversation)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CONTEXT INJECTION (for system prompt enhancement)
    # ═══════════════════════════════════════════════════════════════════════════

    # Get context to inject into the Scout system prompt
    # This is designed to be added WITHOUT replacing the existing prompt
    def get_context_injection
      parts = []

      # Platform health awareness
      health_section = platform_health_section
      parts << health_section if health_section.present?

      # Available specialists summary
      agents_section = available_agents_section
      parts << agents_section if agents_section.present?

      # Active issues awareness
      issues_section = active_issues_section
      parts << issues_section if issues_section.present?

      return "" if parts.empty?

      <<~INJECTION

        ═══════════════════════════════════════════════════════════════
        🔮 LIVE PLATFORM AWARENESS (Real-time Context)
        ═══════════════════════════════════════════════════════════════

        #{parts.join("\n\n")}
      INJECTION
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # ROUTING HINTS (for decision support)
    # ═══════════════════════════════════════════════════════════════════════════

    # Get a routing hint for a user message
    # Returns structured guidance on how to handle the request
    def get_routing_hint(user_message)
      routing = orchestrator.route(user_message)

      {
        recommended_action: routing[:action],
        reason: routing[:reason],
        suggested_agent: routing[:agent],
        suggested_tool: routing[:tool],
        context: routing[:routing_context],
        confidence: routing[:confidence] || 0.8
      }
    end

    # Get a formatted routing hint for prompt injection
    def get_routing_hint_for_prompt(user_message)
      hint = get_routing_hint(user_message)

      case hint[:recommended_action]
      when :answer_directly
        nil # No special hint needed
      when :use_tool
        "💡 HINT: Consider using the `#{hint[:suggested_tool]}` tool for this request."
      when :agent_delegation
        if hint[:suggested_agent]
          "💡 HINT: This request would be well-suited for the `#{hint[:suggested_agent]}` agent."
        end
      when :create_ticket
        "💡 HINT: This sounds like a bug report. Consider using `create_support_ticket`."
      when :human_escalation
        "💡 HINT: This is a sensitive request that may need human approval."
      else
        nil
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CAPABILITY AWARENESS (what can we do?)
    # ═══════════════════════════════════════════════════════════════════════════

    # Check if a capability is available
    def can_do?(capability_name)
      orchestrator.can_do?(capability_name)
    end

    # Get the best agent for a task
    def best_agent_for(task_description)
      orchestrator.best_agent_for(task_description)
    end

    # List all direct capabilities
    def direct_capabilities
      orchestrator.capabilities.direct_capabilities_for_prompt
    end

    # List all available agents
    def agent_capabilities
      orchestrator.capabilities.agent_capabilities_for_prompt
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PLATFORM STATE (for real-time awareness)
    # ═══════════════════════════════════════════════════════════════════════════

    # Get current platform health
    def platform_health
      orchestrator.platform_health
    end

    # Get current ticket summary
    def ticket_summary
      orchestrator.ticket_summary
    end

    # Get active issues
    def active_issues
      orchestrator.awareness.active_issues
    end

    # Get pending PRs
    def pending_prs
      orchestrator.awareness.pending_prs
    end

    private

    def platform_health_section
      health = platform_health
      return nil unless health[:last_check]

      status_emoji = case health[:status]
                     when :excellent then "🟢"
                     when :good then "🟢"
                     when :fair then "🟡"
                     when :poor then "🟠"
                     when :critical then "🔴"
                     else "⚪"
                     end

      <<~SECTION
        📊 PLATFORM STATUS: #{status_emoji} #{health[:status].to_s.capitalize} (#{health[:score_percent]}% health)
        • Active agents: #{health[:active_agents]}
        • 24h success rate: #{health[:success_rate] ? "#{(health[:success_rate] * 100).round}%" : 'N/A'}
        #{health[:critical_anomalies].to_i > 0 ? "• ⚠️ Critical anomalies: #{health[:critical_anomalies]}" : ""}
      SECTION
    end

    def available_agents_section
      agents = orchestrator.available_agents
      return nil if agents.empty?

      agent_list = agents.first(5).map do |agent|
        "• #{agent.name} (#{agent.slug}) - #{agent.description&.truncate(60)}"
      end.join("\n")

      <<~SECTION
        🤖 AVAILABLE SPECIALISTS:
        #{agent_list}
        #{agents.size > 5 ? "• ... and #{agents.size - 5} more agents" : ""}
      SECTION
    end

    def active_issues_section
      tickets = ticket_summary
      return nil if tickets[:open].zero? && tickets[:pending_prs].zero?

      parts = []
      parts << "• Open tickets: #{tickets[:open]}" if tickets[:open].positive?
      parts << "• Critical: #{tickets[:critical]}" if tickets[:critical].positive?
      parts << "• Pending PRs: #{tickets[:pending_prs]}" if tickets[:pending_prs].positive?

      <<~SECTION
        🎫 ACTIVE ISSUES:
        #{parts.join("\n")}
        If user reports a bug, you can check if it's already known or create a new ticket.
      SECTION
    end
  end
end


