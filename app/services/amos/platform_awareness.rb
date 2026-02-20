# frozen_string_literal: true

module Amos
  # PlatformAwareness - Gives AMOS real-time knowledge of system state
  #
  # AMOS should know:
  # - Current platform health
  # - Active tickets and PRs
  # - Recent issues and fixes
  # - Agent performance
  #
  class PlatformAwareness
    attr_reader :entity

    def initialize(entity)
      @entity = entity
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # HEALTH & STATUS
    # ═══════════════════════════════════════════════════════════════════════════

    def current_health
      perception = entity.platform_perceptions.recent.first

      if perception
        {
          score: perception.overall_health_score,
          score_percent: (perception.overall_health_score * 100).round,
          status: health_status(perception.overall_health_score),
          success_rate: perception.success_rate_24h,
          active_agents: perception.active_agents,
          anomaly_count: perception.anomaly_count,
          critical_anomalies: perception.critical_anomalies,
          last_check: perception.perceived_at
        }
      else
        {
          score: 1.0,
          score_percent: 100,
          status: :unknown,
          success_rate: nil,
          active_agents: entity.agent_plugins.where(status: 'active').count,
          anomaly_count: 0,
          critical_anomalies: 0,
          last_check: nil
        }
      end
    end

    def health_status(score)
      case score
      when 0.9..1.0 then :excellent
      when 0.7..0.9 then :good
      when 0.5..0.7 then :fair
      when 0.3..0.5 then :poor
      else :critical
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # TICKETS & ISSUES
    # ═══════════════════════════════════════════════════════════════════════════

    def ticket_summary
      {
        open: SupportTicket.where(entity: entity).open_tickets.count,
        critical: SupportTicket.where(entity: entity).critical.open_tickets.count,
        today: SupportTicket.where(entity: entity).where('created_at > ?', 24.hours.ago).count,
        pending_prs: PullRequestSubmission.joins(:support_ticket)
          .where(support_tickets: { entity_id: entity.id })
          .pending_review.count
      }
    end

    def active_issues
      SupportTicket.where(entity: entity)
        .open_tickets
        .order(priority: :desc, created_at: :desc)
        .limit(5)
        .map do |ticket|
          {
            ticket_number: ticket.ticket_number,
            title: ticket.title.truncate(50),
            priority: ticket.priority,
            status: ticket.status,
            age: time_ago_simple(ticket.created_at)
          }
        end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # EVOLUTION & FIXES
    # ═══════════════════════════════════════════════════════════════════════════

    def evolution_summary
      {
        recent_fixes: CodeFix.joins(:support_ticket)
          .where(support_tickets: { entity_id: entity.id })
          .where(status: 'applied')
          .where('code_fixes.applied_at > ?', 7.days.ago)
          .count,
        pending_fixes: CodeFix.joins(:support_ticket)
          .where(support_tickets: { entity_id: entity.id })
          .validated.count,
        evolution_cycles: EvolutionCycle.where(entity: entity)
          .where('created_at > ?', 7.days.ago).count
      }
    end

    def recent_activity
      activities = []

      # Recent PRs merged
      PullRequestSubmission.joins(:support_ticket)
        .where(support_tickets: { entity_id: entity.id })
        .merged
        .order(merged_at: :desc)
        .limit(3)
        .each do |pr|
          activities << {
            type: :fix_merged,
            description: "Fix merged: #{pr.support_ticket.title.truncate(40)}",
            time: pr.merged_at
          }
        end

      # Recent perception
      perception = entity.platform_perceptions.recent.first
      if perception
        activities << {
          type: :perception,
          description: "Platform health check: #{(perception.overall_health_score * 100).round}%",
          time: perception.perceived_at
        }
      end

      # Recent evolution
      cycle = EvolutionCycle.where(entity: entity).order(created_at: :desc).first
      if cycle
        activities << {
          type: :evolution,
          description: "Evolution cycle: #{cycle.status}",
          time: cycle.created_at
        }
      end

      activities.sort_by { |a| a[:time] }.reverse.first(5)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # AGENT PERFORMANCE
    # ═══════════════════════════════════════════════════════════════════════════

    def agent_performance
      entity.agent_plugins.where(status: 'active').map do |agent|
        executions = agent.agent_plugin_executions
          .where('created_at > ?', 24.hours.ago)

        total = executions.count
        successful = executions.where(status: 'completed').count
        success_rate = total > 0 ? (successful.to_f / total * 100).round : nil

        {
          name: agent.name,
          slug: agent.slug,
          executions_24h: total,
          success_rate: success_rate,
          status: agent_status(success_rate)
        }
      end
    end

    def agent_status(success_rate)
      return :unknown unless success_rate

      case success_rate
      when 90..100 then :excellent
      when 70..90 then :good
      when 50..70 then :needs_attention
      else :critical
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CONTEXT FOR AMOS
    # ═══════════════════════════════════════════════════════════════════════════

    def full_context
      {
        health: current_health,
        tickets: ticket_summary,
        evolution: evolution_summary,
        agents: agent_performance,
        recent_activity: recent_activity
      }
    end

    def summary_for_prompt
      health = current_health
      tickets = ticket_summary

      lines = []
      lines << "**Platform Status**: #{health[:status].to_s.humanize} (#{health[:score_percent]}% health)"
      lines << "**Active Agents**: #{health[:active_agents]}"
      lines << "**Open Tickets**: #{tickets[:open]}#{tickets[:critical] > 0 ? " (#{tickets[:critical]} critical)" : ''}"

      if tickets[:pending_prs] > 0
        lines << "**Pending PRs**: #{tickets[:pending_prs]} awaiting review"
      end

      if health[:anomaly_count] > 0
        lines << "**Anomalies**: #{health[:anomaly_count]} detected"
      end

      lines.join("\n")
    end

    def brief_status
      health = current_health
      tickets = ticket_summary

      status = "Platform is #{health[:status]} at #{health[:score_percent]}% health"

      if tickets[:critical] > 0
        status += " with #{tickets[:critical]} critical issues"
      elsif tickets[:open] > 0
        status += " with #{tickets[:open]} open tickets"
      end

      status
    end

    private

    def time_ago_simple(time)
      seconds = Time.current - time
      case seconds
      when 0..59 then 'just now'
      when 60..3599 then "#{(seconds / 60).round}m ago"
      when 3600..86399 then "#{(seconds / 3600).round}h ago"
      else "#{(seconds / 86400).round}d ago"
      end
    end
  end
end


