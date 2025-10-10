# Stripe Integration - Requirements & Answers

## ✅ Answered Requirements

### Onboarding Flow
- **Flow**: User signup → Stripe checkout (collect CC) → 7-day trial → Onboarding chat
- **Trial**: 7 days, credit card collected immediately, charged after trial
- **Subscription**: Recurring subscription

### Stripe Setup
- **Account**: Need to set up new Stripe account (can use test mode without bank account)
- **Integration**: Already have working Stripe integration
- **Pricing Model**: Base subscription + usage-based tokens (similar to Cursor)
  - Base subscription price includes token allocation
  - Extra charges for tokens over the limit

### Post-Payment Flow
- **After Payment**: User starts onboarding chat wizard
- **Webhooks**: Yes - need to handle subscription updates/cancellations
- **In-Chat Features**: Users can update subscriptions and view billing info via chat

### Pricing Tiers
- Tiers are on the website (directionally correct, may need verification)
- Need to implement usage-based billing for tokens

## 🚧 Implementation Tasks

### Database Schema Additions
- [ ] Entity fields: `stripe_customer_id`, `stripe_subscription_id`, `subscription_status`, `trial_ends_at`, `current_period_end`, `token_usage`, `token_limit`, `plan_tier`
- [ ] Consider: `TokenUsageLog` table for tracking usage over time

### Webhook Events to Handle
- [ ] `customer.subscription.created` - Set up new subscription
- [ ] `customer.subscription.updated` - Update plan/status changes
- [ ] `customer.subscription.deleted` - Handle cancellations
- [ ] `invoice.payment_succeeded` - Confirm payment, reset token usage
- [ ] `invoice.payment_failed` - Mark account as past_due
- [ ] `customer.subscription.trial_will_end` - Send reminder email

### User/Entity States
- [ ] `trial` - In 7-day trial period
- [ ] `active` - Paying subscriber
- [ ] `past_due` - Payment failed
- [ ] `cancelled` - Subscription ended
- [ ] `incomplete` - Checkout not completed

### AI Tools for Chat Interface
- [ ] `get_billing_info` - Show subscription details, next billing date, payment method
- [ ] `update_subscription` - Change plan tier
- [ ] `cancel_subscription` - Cancel service (with confirmation)
- [ ] `get_token_usage` - Show current usage vs limit
- [ ] `view_invoices` - Show billing history

### Controllers & Routes
- [ ] Stripe webhook endpoint (`/webhooks/stripe`)
- [ ] Checkout session creation
- [ ] Customer portal redirect
- [ ] Subscription management endpoints

---

**Next Steps:** Implement Stripe onboarding flow with `/build-feature stripe-onboarding`
