module Tools
  class GetMyAiUsageTool < BaseTool
    def self.metadata
      {
        name: 'get_my_ai_usage',
        description: 'Get AI usage statistics for the current user including conversations, messages, workflows, tokens, and estimated costs',
        category: 'analytics',
        input_schema: {
          type: 'object',
          properties: {
            timeframe: {
              type: 'string',
              enum: ['today', 'week', 'month', 'all'],
              description: 'Time period to get usage for (default: month)'
            }
          }
        }
      }
    end
    
    def execute(args)
      timeframe = get_arg(args, :timeframe, 'month')
      
      start_time = case timeframe
                   when 'today' then 24.hours.ago
                   when 'week' then 7.days.ago
                   when 'month' then 30.days.ago
                   else 1.year.ago
                   end
      
      # Calculate usage stats
      conversations = user.scout_conversations.where(created_at: start_time..).count
      messages = user.scout_messages.where(created_at: start_time..).count
      workflows = user.task_sessions.where(created_at: start_time..).count
      workflows_completed = user.task_sessions.where(status: 'completed', created_at: start_time..).count
      workflows_failed = user.task_sessions.where(status: 'failed', created_at: start_time..).count
      
      # Estimate tokens (will be real when we track actual usage)
      estimated_tokens = messages * 500
      estimated_cost = (estimated_tokens * 0.00002).round(2)
      
      success_response(
        timeframe: timeframe,
        period_start: start_time.strftime("%B %d, %Y"),
        conversations: conversations,
        messages: messages,
        workflows: {
          total: workflows,
          completed: workflows_completed,
          failed: workflows_failed,
          success_rate: workflows > 0 ? ((workflows_completed.to_f / workflows) * 100).round(1) : 0
        },
        ai_usage: {
          estimated_tokens: estimated_tokens,
          estimated_cost: estimated_cost,
          avg_tokens_per_message: messages > 0 ? (estimated_tokens / messages).round(0) : 0
        },
        summary: "In the #{timeframe_label(timeframe)}, you've had #{conversations} conversations with #{messages} messages, completed #{workflows_completed} workflows, using approximately #{number_with_delimiter(estimated_tokens)} tokens (est. cost: $#{estimated_cost})"
      )
    end
    
    private
    
    def timeframe_label(timeframe)
      case timeframe
      when 'today' then 'last 24 hours'
      when 'week' then 'last 7 days'
      when 'month' then 'last 30 days'
      else 'all time'
      end
    end
    
    def number_with_delimiter(number)
      number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
  end
end

