# frozen_string_literal: true

module Tools
  class GetWorkInboxTool < BaseTool
    def self.metadata
      {
        name: "get_work_inbox",
        description: "Get the user's work inbox - a list of completed agent work, scheduled task results, and items requiring attention.",
        category: "scheduling",
        input_schema: {
          type: "object",
          properties: {
            filter: {
              type: "string",
              enum: %w[all unread starred action_required today],
              description: "Filter items: all, unread, starred, action_required, or today. Defaults to 'unread'."
            },
            work_type: {
              type: "string",
              description: "Filter by work type (e.g., 'scheduled_task_completed', 'report_generated')"
            },
            limit: {
              type: "integer",
              description: "Maximum number of items to return. Defaults to 20."
            }
          }
        }
      }
    end

    def execute(args)
      log_execution(args)

      filter = get_arg(args, :filter, 'unread')
      work_type = get_arg(args, :work_type)
      limit = get_arg(args, :limit, 20).to_i

      begin
        items = AgentWorkItem.where(entity: @entity, user: @user)
                            .not_archived
                            .recent

        # Apply filters
        case filter
        when 'unread'
          items = items.unread
        when 'starred'
          items = items.starred
        when 'action_required'
          items = items.requiring_action
        when 'today'
          items = items.today
        # 'all' shows everything
        end

        items = items.where(work_type: work_type) if work_type.present?
        items = items.limit(limit)

        # Get counts
        unread_count = AgentWorkItem.unread_count_for(@user, @entity)
        action_count = AgentWorkItem.action_required_count_for(@user, @entity)

        if items.empty?
          return success_response(
            items: [],
            count: 0,
            unread_count: unread_count,
            action_required_count: action_count,
            message: "Your inbox is empty#{filter != 'all' ? " (filtered by: #{filter})" : ''}."
          )
        end

        item_list = items.map do |item|
          {
            id: item.id,
            icon: item.icon,
            work_type: item.work_type,
            title: item.title,
            summary: item.summary&.truncate(150),
            # Include full details so AI can read the complete output
            details: item.details,
            output: item.details || item.summary, # Alias for clarity
            agent: item.agent_name,
            time: item.time_ago,
            read: item.read?,
            starred: item.starred?,
            priority: item.priority,
            requires_action: item.requires_action?,
            action_type: item.action_type,
            category: item.category,
            # Include asset info if relevant
            asset_type: item.asset_type,
            asset_id: item.asset_id
          }
        end

        success_response(
          items: item_list,
          count: item_list.count,
          unread_count: unread_count,
          action_required_count: action_count,
          message: "Found #{item_list.count} item(s) in your inbox. #{unread_count} unread, #{action_count} requiring action."
        )
      rescue => e
        Rails.logger.error "Error getting work inbox: #{e.message}"
        error_response("Failed to get work inbox: #{e.message}")
      end
    end
  end
end

