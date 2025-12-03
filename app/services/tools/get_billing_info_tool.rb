# frozen_string_literal: true

module Tools
  class GetBillingInfoTool < BaseTool
    def self.metadata
      {
        name: 'get_billing_info',
        description: 'Get billing information including AMOS Work Token balance, usage this month, spending limits, auto-replenishment settings, and payment method. Use this when the user asks about their balance, billing, usage, costs, or tokens.',
        category: 'billing',
        input_schema: {
          type: 'object',
          properties: {
            include_usage_breakdown: {
              type: 'boolean',
              description: 'Include detailed breakdown of token usage by category (AI, email, storage, etc.)'
            },
            include_recent_transactions: {
              type: 'boolean',
              description: 'Include recent token transactions'
            }
          },
          required: []
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)

      include_breakdown = get_arg(args, :include_usage_breakdown, false)
      include_transactions = get_arg(args, :include_recent_transactions, false)

      begin
        # Get or create billing account
        billing_account = UserBillingAccount.for_user(user)
        config = BillingConfiguration.current
        
        # Core balance info
        balance_info = {
          current_balance: billing_account.work_token_balance,
          current_balance_formatted: number_with_delimiter(billing_account.work_token_balance),
          free_tokens_remaining: billing_account.free_tokens_remaining,
          low_balance: billing_account.low_balance?,
          estimated_value_usd: config.tokens_to_usd(billing_account.work_token_balance)
        }

        # Monthly usage
        monthly_info = {
          tokens_used_this_month: billing_account.usage_this_month,
          tokens_used_formatted: number_with_delimiter(billing_account.usage_this_month),
          spending_this_month_usd: billing_account.spending_this_month_usd.round(2),
          monthly_limit_usd: billing_account.monthly_limit_usd,
          within_monthly_limit: billing_account.within_monthly_limit?,
          monthly_limit_percent_used: billing_account.monthly_limit_usd > 0 ? 
            ((billing_account.spending_this_month_usd / billing_account.monthly_limit_usd) * 100).round(1) : 0
        }

        # Auto-replenishment settings
        auto_replenish_info = {
          enabled: billing_account.auto_replenish_enabled?,
          amount_usd: billing_account.auto_replenish_amount_usd,
          has_payment_method: billing_account.has_payment_method?,
          last_replenishment: billing_account.last_replenishment_at&.strftime('%B %d, %Y at %I:%M %p')
        }

        # Lifetime stats
        lifetime_info = {
          total_tokens_purchased: billing_account.lifetime_tokens_purchased,
          total_tokens_used: billing_account.lifetime_tokens_used
        }

        # Payment method info
        payment_info = billing_account.payment_method_details

        result = {
          balance: balance_info,
          monthly_usage: monthly_info,
          auto_replenishment: auto_replenish_info,
          lifetime_stats: lifetime_info,
          payment_method: payment_info,
          pricing: {
            uplift_percentage: config.uplift_percentage,
            work_token_value: "$#{BillingConfiguration::WORK_TOKEN_VALUE} per token"
          }
        }

        # Add usage breakdown by category if requested
        if include_breakdown
          work_token_service = WorkTokenService.new(user: user, entity: entity)
          usage_summary = work_token_service.usage_summary(days: 30)
          
          result[:usage_breakdown] = {
            period: 'Last 30 days',
            by_category: usage_summary[:by_category].transform_keys do |key|
              case key
              when 'ai_tokens' then 'AI Usage'
              when 'email' then 'Email Sending'
              when 'storage' then 'Storage'
              when 'api_call' then 'API Calls'
              when 'other_compute' then 'Other Compute'
              else key.titleize
              end
            end,
            total_tokens: usage_summary[:total_tokens]
          }
        end

        # Add recent transactions if requested
        if include_transactions
          work_token_service ||= WorkTokenService.new(user: user, entity: entity)
          recent = work_token_service.recent_transactions(limit: 10)
          
          result[:recent_transactions] = recent.map do |tx|
            {
              date: tx.created_at.strftime('%b %d, %Y'),
              type: tx.transaction_type,
              category: tx.category_label,
              amount: tx.formatted_amount,
              description: tx.description
            }
          end
        end

        # Build a friendly summary
        summary = build_summary(balance_info, monthly_info, auto_replenish_info)

        success_response(
          billing_info: result,
          summary: summary,
          message: "Retrieved billing information successfully"
        )
      rescue => e
        Rails.logger.error "GetBillingInfoTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Failed to retrieve billing information: #{e.message}")
      end
    end

    private

    def build_summary(balance, monthly, auto_replenish)
      parts = []
      
      # Balance status
      if balance[:low_balance]
        parts << "⚠️ Your balance is low at #{balance[:current_balance_formatted]} work tokens (~$#{balance[:estimated_value_usd]})."
        if auto_replenish[:enabled] && auto_replenish[:has_payment_method]
          parts << "Auto-replenishment is enabled and will add $#{auto_replenish[:amount_usd]} when needed."
        else
          parts << "Consider adding more tokens to avoid service interruption."
        end
      else
        parts << "✅ You have #{balance[:current_balance_formatted]} work tokens (~$#{balance[:estimated_value_usd]})."
      end

      # Free tokens
      if balance[:free_tokens_remaining] > 0
        parts << "This includes #{number_with_delimiter(balance[:free_tokens_remaining])} free tokens."
      end

      # Monthly usage
      parts << "This month you've used #{monthly[:tokens_used_formatted]} tokens (~$#{monthly[:spending_this_month_usd]})."
      
      if monthly[:monthly_limit_usd] > 0
        parts << "You're at #{monthly[:monthly_limit_percent_used]}% of your $#{monthly[:monthly_limit_usd]} monthly limit."
      end

      parts.join(" ")
    end

    def number_with_delimiter(number)
      number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
  end
end
