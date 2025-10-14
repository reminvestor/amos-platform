# Subscription Event Tracking

This app now tracks all subscription lifecycle events in the `subscription_events` table.

## Rails Console Usage

### Quick Access

```ruby
# Get your entity
entity = Entity.first
# or
entity = Entity.find_by(name: "My Company")

# Print formatted subscription history
entity.print_subscription_history

# Get statistics
entity.subscription_stats

# Get history as data (for API/export)
entity.subscription_history
```

### Example Output

```ruby
entity.print_subscription_history
```

```
================================================================================
Subscription History for: My Company
================================================================================

2025-10-13 21:51:35
  Event: subscription_created
  Status: none → trialing
  Plan: none → professional
  Triggered by: user_checkout
  Metadata: {"token_limit"=>1000000, "trial_ends_at"=>"2025-10-20", ...}

2025-10-20 14:30:22
  Event: payment_succeeded
  Status: trialing → active
  Triggered by: stripe_webhook
  Metadata: {"amount_paid"=>11900, "invoice_id"=>"in_123", ...}

================================================================================
Total Events: 2
================================================================================
```

### Statistics

```ruby
entity.subscription_stats
# => {
#   total_events: 5,
#   subscriptions_created: 1,
#   subscriptions_cancelled: 0,
#   plan_changes: 1,
#   payment_failures: 0,
#   payment_successes: 3,
#   first_subscription: 2025-10-13 21:51:35 UTC,
#   last_event: 2025-11-13 10:15:42 UTC
# }
```

### Advanced Queries

```ruby
# Get all subscription creation events
entity.subscription_events.where(event_type: 'subscription_created')

# Get cancellations
entity.subscription_events.where(event_type: 'subscription_cancelled')

# Get payment failures
entity.subscription_events.where(event_type: 'payment_failed')

# Get events from last 30 days
entity.subscription_events.where('created_at > ?', 30.days.ago)

# Get events triggered by users (not webhooks)
entity.subscription_events.where(triggered_by: 'user_action')

# Get specific event details
event = entity.subscription_events.last
event.metadata  # JSON data with extra details
event.status_changed?  # true/false
event.plan_changed?  # true/false
```

## Event Types

- `subscription_created` - Customer signs up
- `subscription_updated` - Subscription modified
- `subscription_cancelled` - Customer cancels
- `subscription_reactivated` - Customer resumes
- `plan_changed` - Customer upgrades/downgrades
- `trial_started` - Trial begins
- `trial_ended` - Trial expires
- `payment_succeeded` - Successful payment
- `payment_failed` - Failed payment

## Triggered By

- `user_checkout` - User completed Stripe checkout
- `user_action` - User cancelled via app
- `stripe_webhook` - Automatic Stripe event
- `admin_action` - Manual admin change

## What's Logged

Each event records:
- Previous and new subscription status
- Previous and new plan tier
- Stripe event ID (for deduplication)
- Metadata (trial dates, amounts, feedback, etc.)
- Who/what triggered it
- Timestamp

## Use Cases

1. **Customer Support** - See full subscription history when helping customers
2. **Analytics** - Track churn, upgrades, payment issues
3. **Debugging** - Understand what happened and when
4. **Compliance** - Audit trail for subscriptions
5. **Reporting** - Generate subscription lifecycle reports
