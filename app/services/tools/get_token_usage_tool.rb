module Tools
  class GetTokenUsageTool < BaseTool
    def self.metadata
      {
        name: 'get_token_usage',
        description: 'Get current token usage statistics including usage count, limit, percentage used, and overage charges if applicable',
        input_schema: {
          type: 'object',
          properties: {},
          required: []
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)

      token_usage = entity.token_usage || 0
      token_limit = entity.token_limit || 100_000
      tokens_remaining = [token_limit - token_usage, 0].max
      usage_percent = token_limit > 0 ? ((token_usage.to_f / token_limit) * 100).round(2) : 0

      # Calculate overage
      overage_tokens = token_usage > token_limit ? (token_usage - token_limit) : 0
      overage_cost = (overage_tokens / 1000.0 * 0.01).round(2) # $0.01 per 1000 tokens over limit

      # Determine status
      status = if usage_percent < 70
        'healthy'
      elsif usage_percent < 90
        'warning'
      else
        'critical'
      end

      usage_info = {
        token_usage: token_usage,
        token_limit: token_limit,
        tokens_remaining: tokens_remaining,
        usage_percent: usage_percent,
        status: status,
        overage_tokens: overage_tokens,
        estimated_overage_cost: overage_cost > 0 ? "$#{overage_cost}" : nil,
        plan_tier: entity.plan_tier&.titleize || 'Basic',
        current_period_end: entity.current_period_end&.strftime('%B %d, %Y')
      }

      message = if overage_tokens > 0
        "You've used #{usage_percent}% of your tokens (#{token_usage.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} / #{token_limit.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}). You have #{overage_tokens.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} tokens in overage with an estimated cost of $#{overage_cost}."
      elsif usage_percent >= 90
        "Warning: You've used #{usage_percent}% of your tokens. Consider upgrading your plan."
      elsif usage_percent >= 70
        "You've used #{usage_percent}% of your tokens. You're approaching your limit."
      else
        "You have #{tokens_remaining.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} tokens remaining (#{usage_percent}% used)."
      end

      success_response(
        usage_info: usage_info,
        message: message
      )
    end
  end
end
