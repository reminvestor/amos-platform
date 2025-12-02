# frozen_string_literal: true

module Tools
  class GetMyAiUsageTool < BaseTool
    def self.metadata
      {
        name: "get_my_ai_usage",
        description: "Get detailed AI and platform usage statistics including conversations, messages, workflows, work token consumption by category, and costs. Use this when the user asks about their usage, activity, or how much they've used.",
        category: "analytics",
        input_schema: {
          type: "object",
          properties: {
            timeframe: {
              type: "string",
              enum: ["today", "week", "month", "all"],
              description: "Time period to get usage for (default: month)"
            }
          }
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)
      
      timeframe = get_arg(args, :timeframe, "month")

      start_time = case timeframe
      when "today" then 24.hours.ago
      when "week" then 7.days.ago
      when "month" then 30.days.ago
      else 1.year.ago
      end

      # Get billing account and config
      billing_account = UserBillingAccount.for_user(user)
      config = BillingConfiguration.current

      # Calculate activity stats
      conversations = user.scout_conversations.where(created_at: start_time..).count
      messages = user.scout_messages.where(created_at: start_time..).count
      workflows = user.task_sessions.where(created_at: start_time..).count
      workflows_completed = user.task_sessions.where(status: "completed", created_at: start_time..).count
      workflows_failed = user.task_sessions.where(status: "failed", created_at: start_time..).count

      # Get real work token usage from transactions
      transactions = billing_account.work_token_transactions
        .where(created_at: start_time..)
        .where(transaction_type: 'debit')

      total_tokens_used = transactions.sum(:amount)
      total_raw_cost_cents = transactions.sum(:raw_cost_cents)
      total_uplifted_cost_cents = transactions.sum(:uplifted_cost_cents)

      # Usage by category
      usage_by_category = transactions.group(:category).sum(:amount)
      cost_by_category = transactions.group(:category).sum(:uplifted_cost_cents)

      # Format category data
      formatted_categories = {}
      usage_by_category.each do |category, tokens|
        label = case category
        when 'ai_tokens' then '🤖 AI Usage'
        when 'email' then '📧 Email'
        when 'storage' then '💾 Storage'
        when 'api_call' then '🔌 API Calls'
        when 'other_compute' then '☁️ Other Compute'
        else category&.titleize || 'Other'
        end
        
        formatted_categories[label] = {
          tokens: tokens,
          tokens_formatted: number_with_delimiter(tokens),
          cost_usd: (cost_by_category[category].to_f / 100).round(2)
        }
      end

      # Integration stats
      integration_calls = IntegrationLog.joins(connection: :entity)
        .where(connections: { entity_id: entity.id })
        .where(created_at: start_time..).count
      
      integration_errors = IntegrationLog.joins(connection: :entity)
        .where(connections: { entity_id: entity.id })
        .where("response_status >= 400")
        .where(created_at: start_time..).count

      result = {
        timeframe: timeframe,
        period_start: start_time.strftime("%B %d, %Y"),
        period_end: Time.current.strftime("%B %d, %Y"),
        
        activity: {
          conversations: conversations,
          messages: messages,
          avg_messages_per_conversation: conversations > 0 ? (messages.to_f / conversations).round(1) : 0
        },
        
        workflows: {
          total: workflows,
          completed: workflows_completed,
          failed: workflows_failed,
          success_rate: workflows > 0 ? ((workflows_completed.to_f / workflows) * 100).round(1) : 0
        },
        
        integrations: {
          api_calls: integration_calls,
          errors: integration_errors,
          error_rate: integration_calls > 0 ? ((integration_errors.to_f / integration_calls) * 100).round(1) : 0
        },
        
        work_tokens: {
          total_used: total_tokens_used,
          total_used_formatted: number_with_delimiter(total_tokens_used),
          raw_cost_usd: (total_raw_cost_cents / 100.0).round(2),
          total_cost_usd: (total_uplifted_cost_cents / 100.0).round(2),
          by_category: formatted_categories
        },
        
        current_balance: {
          tokens: billing_account.work_token_balance,
          tokens_formatted: number_with_delimiter(billing_account.work_token_balance),
          estimated_value_usd: config.tokens_to_usd(billing_account.work_token_balance)
        }
      }

      # Build summary
      summary = build_summary(timeframe, result)

      success_response(result.merge(summary: summary))
    end

    private

    def build_summary(timeframe, data)
      period = timeframe_label(timeframe)
      
      parts = []
      parts << "📊 In the #{period}:"
      parts << "• #{data[:activity][:conversations]} conversations with #{data[:activity][:messages]} messages"
      
      if data[:workflows][:total] > 0
        parts << "• #{data[:workflows][:completed]}/#{data[:workflows][:total]} workflows completed (#{data[:workflows][:success_rate]}% success)"
      end
      
      if data[:integrations][:api_calls] > 0
        parts << "• #{data[:integrations][:api_calls]} integration API calls"
      end
      
      parts << "• #{data[:work_tokens][:total_used_formatted]} work tokens used (~$#{data[:work_tokens][:total_cost_usd]})"
      
      # Top category
      if data[:work_tokens][:by_category].any?
        top_category = data[:work_tokens][:by_category].max_by { |_, v| v[:tokens] }
        if top_category
          parts << "• Top usage: #{top_category[0]} (#{top_category[1][:tokens_formatted]} tokens)"
        end
      end
      
      parts << "\n💰 Current balance: #{data[:current_balance][:tokens_formatted]} tokens (~$#{data[:current_balance][:estimated_value_usd]})"
      
      parts.join("\n")
    end

    def timeframe_label(timeframe)
      case timeframe
      when "today" then "last 24 hours"
      when "week" then "last 7 days"
      when "month" then "last 30 days"
      else "all time"
      end
    end

    def number_with_delimiter(number)
      number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
  end
end
