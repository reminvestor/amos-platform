module Tools
  class UpdateSubscriptionTool < BaseTool
    def self.metadata
      {
        name: 'update_subscription',
        description: 'Update subscription plan tier (starter, professional, enterprise)',
        input_schema: {
          type: 'object',
          properties: {
            plan_tier: {
              type: 'string',
              description: 'The plan tier to upgrade/downgrade to',
              enum: ['starter', 'professional', 'enterprise']
            }
          },
          required: ['plan_tier']
        }
      }
    end

    def execute(args)
      log_execution(args)

      validation_error = validate_required_args(args, [:plan_tier])
      return validation_error if validation_error

      plan_tier = get_arg(args, :plan_tier).downcase

      unless entity.stripe_subscription_id.present?
        return error_response("No active subscription found. Please subscribe first.")
      end

      begin
        subscription = Stripe::Subscription.retrieve(entity.stripe_subscription_id)

        # Get the price ID for the new plan tier
        price_id = get_price_id_for_tier(plan_tier)

        unless price_id
          return error_response("Invalid plan tier: #{plan_tier}. Valid options are: starter, professional, enterprise")
        end

        # Update the subscription
        updated_subscription = Stripe::Subscription.update(
          subscription.id,
          items: [{
            id: subscription.items.data.first.id,
            price: price_id
          }],
          proration_behavior: 'create_prorations'
        )

        # Update entity
        entity.update!(
          plan_tier: plan_tier,
          token_limit: determine_token_limit(plan_tier)
        )

        success_response(
          subscription: {
            id: updated_subscription.id,
            status: updated_subscription.status,
            plan_tier: plan_tier,
            token_limit: entity.token_limit
          },
          message: "Successfully updated subscription to #{plan_tier.titleize} plan"
        )
      rescue Stripe::StripeError => e
        error_response("Failed to update subscription: #{e.message}")
      end
    end

    private

    def get_price_id_for_tier(tier)
      case tier
      when 'starter', 'basic'
        ENV['STRIPE_STARTER_PRICE_ID']
      when 'professional', 'pro'
        ENV['STRIPE_PROFESSIONAL_PRICE_ID']
      when 'business'
        ENV['STRIPE_BUSINESS_PRICE_ID']
      when 'enterprise'
        ENV['STRIPE_ENTERPRISE_PRICE_ID']
      else
        nil
      end
    end

    def determine_token_limit(tier)
      case tier
      when 'starter', 'basic'
        200_000
      when 'professional', 'pro'
        1_000_000
      when 'business'
        2_000_000
      when 'enterprise'
        2_000_000
      else
        200_000
      end
    end
  end
end
