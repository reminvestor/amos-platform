# frozen_string_literal: true

# Service for sending marketplace-related notifications
# Handles agent/tool approval, rejection, and update notifications
class MarketplaceNotificationService
  class << self
    # ============================================
    # AGENT NOTIFICATIONS
    # ============================================
    
    # Notify agent owner that their agent was approved
    def notify_agent_approved(agent)
      return unless agent.user.present?
      
      UserNotification.create!(
        entity: agent.entity,
        user: agent.user,
        notification_type: 'agent_approved',
        title: "🎉 Agent Approved: #{agent.name}",
        body: "Your agent '#{agent.name}' has been approved and is now available in the public marketplace!",
        channel: 'both',
        priority: 'high',
        action_url: "/admin/agent_plugins/#{agent.id}",
        action_type: 'view',
        metadata: {
          agent_id: agent.id,
          agent_slug: agent.slug,
          agent_name: agent.name
        }
      )
    end

    # Notify agent owner that their agent was rejected
    def notify_agent_rejected(agent, reason: nil)
      return unless agent.user.present?
      
      body = "Your agent '#{agent.name}' was not approved for the public marketplace."
      body += "\n\nReason: #{reason}" if reason.present?
      body += "\n\nPlease review and make the necessary changes before resubmitting."
      
      UserNotification.create!(
        entity: agent.entity,
        user: agent.user,
        notification_type: 'agent_rejected',
        title: "Agent Not Approved: #{agent.name}",
        body: body,
        channel: 'both',
        priority: 'high',
        action_url: "/admin/agent_plugins/#{agent.id}/edit",
        action_type: 'edit',
        metadata: {
          agent_id: agent.id,
          agent_slug: agent.slug,
          agent_name: agent.name,
          rejection_reason: reason
        }
      )
    end

    # Notify agent owner that their submission is pending review
    def notify_agent_pending_review(agent)
      return unless agent.user.present?
      
      UserNotification.create!(
        entity: agent.entity,
        user: agent.user,
        notification_type: 'agent_pending_review',
        title: "Agent Submitted: #{agent.name}",
        body: "Your agent '#{agent.name}' has been submitted for review. You'll be notified once it's been reviewed.",
        channel: 'in_app',
        priority: 'normal',
        action_url: "/admin/agent_plugins/#{agent.id}",
        action_type: 'view',
        metadata: {
          agent_id: agent.id,
          agent_slug: agent.slug,
          agent_name: agent.name
        }
      )
    end

    # Notify users who favorited an agent when it's updated
    def notify_agent_updated(agent, change_summary: nil)
      # Find all users who have favorited this agent (excluding the owner)
      favorite_users = UserFavorite.where(
        favoritable_type: 'AgentPlugin',
        favoritable_id: agent.id
      ).where.not(user_id: agent.user_id).includes(:user, :entity)

      favorite_users.find_each do |favorite|
        UserNotification.create!(
          entity: favorite.entity,
          user: favorite.user,
          notification_type: 'agent_updated',
          title: "Agent Updated: #{agent.name}",
          body: change_summary || "The agent '#{agent.name}' that you favorited has been updated.",
          channel: 'in_app',
          priority: 'low',
          action_url: "/agents/#{agent.slug}",
          action_type: 'view',
          metadata: {
            agent_id: agent.id,
            agent_slug: agent.slug,
            agent_name: agent.name,
            change_summary: change_summary
          }
        )
      end
    end

    # ============================================
    # TOOL NOTIFICATIONS
    # ============================================
    
    # Notify tool owner that their tool was approved
    def notify_tool_approved(tool)
      creator = tool.created_by || tool.user
      return unless creator.present?
      
      UserNotification.create!(
        entity: tool.entity,
        user: creator,
        notification_type: 'tool_approved',
        title: "🛠️ Tool Approved: #{tool.name}",
        body: "Your tool '#{tool.name}' has been approved and is now available in the public marketplace!",
        channel: 'both',
        priority: 'high',
        action_url: "/admin/tool_definitions/#{tool.id}",
        action_type: 'view',
        metadata: {
          tool_id: tool.id,
          tool_name: tool.name
        }
      )
    end

    # Notify tool owner that their tool was rejected
    def notify_tool_rejected(tool, reason: nil)
      creator = tool.created_by || tool.user
      return unless creator.present?
      
      body = "Your tool '#{tool.name}' was not approved for the public marketplace."
      body += "\n\nReason: #{reason}" if reason.present?
      body += "\n\nPlease review and make the necessary changes before resubmitting."
      
      UserNotification.create!(
        entity: tool.entity,
        user: creator,
        notification_type: 'tool_rejected',
        title: "Tool Not Approved: #{tool.name}",
        body: body,
        channel: 'both',
        priority: 'high',
        action_url: "/admin/tool_definitions/#{tool.id}/edit",
        action_type: 'edit',
        metadata: {
          tool_id: tool.id,
          tool_name: tool.name,
          rejection_reason: reason
        }
      )
    end

    # ============================================
    # ADMIN NOTIFICATIONS
    # ============================================
    
    # Notify admins that a new agent is pending review
    def notify_admins_agent_pending(agent)
      # Find all admin users for the entity
      admins = User.where(entity: agent.entity).joins(:entity_users)
                   .where(entity_users: { role: %w[admin owner] })

      admins.find_each do |admin|
        UserNotification.create!(
          entity: agent.entity,
          user: admin,
          notification_type: 'action_required',
          title: "Agent Needs Review: #{agent.name}",
          body: "A new agent '#{agent.name}' by #{agent.user&.name || 'Unknown'} is waiting for review.",
          channel: 'in_app',
          priority: 'normal',
          action_url: "/admin/agent_plugins/#{agent.id}",
          action_type: 'review',
          metadata: {
            agent_id: agent.id,
            agent_slug: agent.slug,
            agent_name: agent.name,
            submitted_by: agent.user_id
          }
        )
      end
    end

    # Notify admins that a new tool is pending review
    def notify_admins_tool_pending(tool)
      # Find all admin users for the entity
      admins = User.where(entity: tool.entity).joins(:entity_users)
                   .where(entity_users: { role: %w[admin owner] })

      admins.find_each do |admin|
        UserNotification.create!(
          entity: tool.entity,
          user: admin,
          notification_type: 'action_required',
          title: "Tool Needs Review: #{tool.name}",
          body: "A new tool '#{tool.name}' by #{tool.created_by&.name || 'Unknown'} is waiting for security review.",
          channel: 'in_app',
          priority: 'normal',
          action_url: "/admin/tool_definitions/#{tool.id}",
          action_type: 'review',
          metadata: {
            tool_id: tool.id,
            tool_name: tool.name,
            submitted_by: tool.created_by_id
          }
        )
      end
    end

    # ============================================
    # REPUTATION NOTIFICATIONS
    # ============================================
    
    # Notify when agent reaches a reputation milestone
    def notify_reputation_milestone(agent, milestone)
      return unless agent.user.present?
      
      milestones = {
        first_use: { title: "First Use!", body: "Your agent '#{agent.name}' was used for the first time!" },
        ten_uses: { title: "10 Uses!", body: "Your agent '#{agent.name}' has been used 10 times!" },
        fifty_uses: { title: "50 Uses!", body: "Your agent '#{agent.name}' has been used 50 times!" },
        hundred_uses: { title: "100 Uses! 🎯", body: "Your agent '#{agent.name}' has reached 100 uses!" },
        high_rating: { title: "Highly Rated! ⭐", body: "Your agent '#{agent.name}' has achieved a high user rating!" },
        elo_1500: { title: "ELO 1500!", body: "Your agent '#{agent.name}' has reached ELO 1500!" },
        elo_1800: { title: "Elite Agent! 🏆", body: "Your agent '#{agent.name}' has reached ELO 1800 - Elite status!" }
      }
      
      config = milestones[milestone.to_sym]
      return unless config

      UserNotification.create!(
        entity: agent.entity,
        user: agent.user,
        notification_type: 'reputation_milestone',
        title: config[:title],
        body: config[:body],
        channel: 'in_app',
        priority: 'normal',
        action_url: "/admin/agent_plugins/#{agent.id}",
        action_type: 'view',
        metadata: {
          agent_id: agent.id,
          agent_slug: agent.slug,
          agent_name: agent.name,
          milestone: milestone
        }
      )
    end
  end
end

