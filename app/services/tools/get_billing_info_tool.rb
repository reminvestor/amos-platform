module Tools
  class GetBillingInfoTool < BaseTool
    def self.metadata
      {
        name: 'get_billing_info',
        description: 'Get billing information including subscription status, plan tier, next billing date, payment method, and token usage',
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

      unless entity.stripe_customer_id.present?
        return error_response("No billing information available. You haven't subscribed yet.")
      end

      begin
        customer = Stripe::Customer.retrieve(entity.stripe_customer_id)
        subscription = entity.stripe_subscription_id.present? ?
          Stripe::Subscription.retrieve(entity.stripe_subscription_id) : nil

        # Get payment method
        payment_method_info = nil
        if customer.invoice_settings&.default_payment_method
          pm = Stripe::PaymentMethod.retrieve(customer.invoice_settings.default_payment_method)
          payment_method_info = {
            type: pm.type,
            card_brand: pm.card&.brand,
            last4: pm.card&.last4,
            exp_month: pm.card&.exp_month,
            exp_year: pm.card&.exp_year
          }
        end

        # Calculate token usage percentage
        token_usage_percent = entity.token_limit && entity.token_limit > 0 ?
          ((entity.token_usage.to_f / entity.token_limit) * 100).round(2) : 0

        billing_info = {
          subscription_status: entity.subscription_status,
          plan_tier: entity.plan_tier&.titleize || 'Basic',
          trial_ends_at: entity.trial_ends_at&.strftime('%B %d, %Y'),
          next_billing_date: entity.current_period_end&.strftime('%B %d, %Y'),
          token_usage: entity.token_usage || 0,
          token_limit: entity.token_limit || 100_000,
          token_usage_percent: token_usage_percent,
          payment_method: payment_method_info,
          customer_email: customer.email
        }

        # Add upcoming invoice if available
        if subscription
          begin
            upcoming_invoice = Stripe::Invoice.upcoming(customer: entity.stripe_customer_id)
            billing_info[:upcoming_invoice] = {
              amount: (upcoming_invoice.amount_due / 100.0),
              currency: upcoming_invoice.currency.upcase,
              period_start: Time.at(upcoming_invoice.period_start).strftime('%B %d, %Y'),
              period_end: Time.at(upcoming_invoice.period_end).strftime('%B %d, %Y')
            }
          rescue Stripe::InvalidRequestError
            # No upcoming invoice
          end
        end

        success_response(
          billing_info: billing_info,
          message: "Retrieved billing information successfully"
        )
      rescue Stripe::StripeError => e
        error_response("Failed to retrieve billing information: #{e.message}")
      end
    end
  end
end
