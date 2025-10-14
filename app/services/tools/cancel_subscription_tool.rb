module Tools
  class CancelSubscriptionTool < BaseTool
    def self.metadata
      {
        name: 'cancel_subscription',
        description: 'Cancel the current subscription. Subscription will remain active until the end of the current billing period.',
        input_schema: {
          type: 'object',
          properties: {
            confirm: {
              type: 'boolean',
              description: 'Must be true to confirm cancellation'
            },
            feedback: {
              type: 'string',
              description: 'Optional feedback about why the subscription is being cancelled'
            }
          },
          required: ['confirm']
        }
      }
    end

    def execute(args)
      log_execution(args)

      validation_error = validate_required_args(args, [:confirm])
      return validation_error if validation_error

      unless get_arg(args, :confirm) == true
        return error_response("Cancellation must be confirmed by setting confirm to true")
      end

      unless entity.stripe_subscription_id.present?
        return error_response("No active subscription found")
      end

      begin
        subscription = Stripe::Subscription.retrieve(entity.stripe_subscription_id)

        # Capture previous state
        previous_status = entity.subscription_status
        previous_plan = entity.plan_tier

        # Cancel at period end (not immediately)
        cancelled_subscription = Stripe::Subscription.update(
          subscription.id,
          cancel_at_period_end: true,
          cancellation_details: {
            comment: get_arg(args, :feedback)
          }
        )

        end_date = Time.at(cancelled_subscription.current_period_end).strftime('%B %d, %Y')

        # Log cancellation event
        SubscriptionEvent.log_event(
          entity: entity,
          event_type: 'subscription_cancelled',
          previous_status: previous_status,
          new_status: 'cancelling',
          previous_plan: previous_plan,
          new_plan: previous_plan,
          stripe_event_id: cancelled_subscription.id,
          metadata: {
            cancel_at_period_end: true,
            current_period_end: cancelled_subscription.current_period_end,
            cancellation_feedback: get_arg(args, :feedback),
            cancelled_by_user: true
          },
          triggered_by: 'user_action'
        )

        success_response(
          subscription: {
            id: cancelled_subscription.id,
            status: cancelled_subscription.status,
            cancel_at_period_end: true,
            current_period_end: end_date
          },
          message: "Subscription will be cancelled on #{end_date}. You'll continue to have access until then."
        )
      rescue Stripe::StripeError => e
        error_response("Failed to cancel subscription: #{e.message}")
      end
    end
  end
end
