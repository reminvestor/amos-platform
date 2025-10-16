# Stripe Billing - User Chat Commands

Users can manage their subscriptions entirely through the AMOS chat interface using natural language.

## Available Commands

### Check Billing Information
Users can ask:
- "What's my billing info?"
- "Show me my subscription details"
- "When is my next billing date?"
- "What payment method do I have on file?"

**Returns:**
- Current plan tier
- Subscription status
- Next billing date
- Payment method (last 4 digits)
- Token usage and limits
- Upcoming invoice amount

---

### Check Token Usage
Users can ask:
- "How many tokens have I used?"
- "How many tokens do I have left?"
- "Am I close to my limit?"
- "Show my token usage"

**Returns:**
- Current token usage
- Token limit for their plan
- Percentage used
- Tokens remaining
- Status (healthy/warning/critical)
- Overage charges if applicable ($0.01 per 1,000 tokens over limit)

---

### Upgrade/Downgrade Plan
Users can ask:
- "Upgrade to professional"
- "Upgrade my plan to pro"
- "Switch to the business plan"
- "Change my subscription to starter"

**Supported Plans:**
- `starter` - $29/month, 200k tokens
- `professional` (or `pro`) - $119/month, 1M tokens
- `business` - $299/month, 2M tokens

**Behavior:**
- Prorated charges/credits applied immediately
- Changes take effect right away
- User is notified of the proration

---

### View Invoice History
Users can ask:
- "Show me my invoices"
- "What have I been charged?"
- "Show my billing history"
- "Display my last 5 invoices"

**Returns:**
- Invoice number
- Amount paid
- Date
- Billing period
- Payment status
- Links to PDF and hosted invoice

**Options:**
- Default: Shows last 10 invoices
- Can request specific number: "Show me my last 20 invoices"

---

### Cancel Subscription
Users can ask:
- "Cancel my subscription"
- "I want to cancel my plan"
- "Stop my subscription"

**Requires:**
- Explicit confirmation (the AI will ask: "Are you sure?")
- Optional: Reason for cancellation

**Behavior:**
- Cancels at period end (not immediately)
- User retains access until end of current billing period
- Can provide feedback about why they're cancelling

---

## Token Limits by Plan

| Plan | Monthly Tokens | Price |
|------|----------------|-------|
| Starter | 200,000 | $29 |
| Professional | 1,000,000 | $119 |
| Business | 2,000,000 | $299 |
| Enterprise | 2,000,000+ | Custom |

**Overage Charges:** $0.01 per 1,000 tokens over the monthly limit

---

## Subscription States

- `trial` - User is in 7-day free trial
- `active` - Subscription is active and paid
- `past_due` - Payment failed, subscription at risk
- `cancelled` - Subscription has been cancelled
- `incomplete` - Checkout session not completed

---

## Example Conversations

### Example 1: Checking Usage
**User:** "How many tokens have I used this month?"

**AMOS:** "You've used 150,000 tokens out of your 200,000 token limit (75% used). You have 50,000 tokens remaining. Your usage is in the warning zone - consider upgrading to the Professional plan for 1M tokens per month."

### Example 2: Upgrading Plan
**User:** "Upgrade to professional"

**AMOS:** "I'll upgrade your subscription to the Professional plan. This will increase your token limit from 200,000 to 1,000,000 tokens per month, and your monthly cost will change from $29 to $119. You'll receive a prorated charge of approximately $72 for the remainder of your current billing period. Shall I proceed?"

**User:** "Yes"

**AMOS:** "Successfully upgraded your subscription to Professional plan! Your new token limit of 1,000,000 tokens is now active."

### Example 3: Viewing Invoices
**User:** "Show me my invoices"

**AMOS:** "Here are your recent invoices:

1. INV-001 - $119.00 (Paid) - December 1, 2024
   Period: Dec 1 - Jan 1, 2025
   [View PDF] [View Online]

2. INV-002 - $119.00 (Paid) - November 1, 2024
   Period: Nov 1 - Dec 1, 2024
   [View PDF] [View Online]

You've been charged $238.00 total across 2 invoices."

### Example 4: Cancellation
**User:** "I want to cancel my subscription"

**AMOS:** "I understand you'd like to cancel your subscription. Your subscription will remain active until January 1, 2025 (the end of your current billing period), and you won't be charged again after that. Are you sure you want to proceed with cancellation?"

**User:** "Yes, it's too expensive for me right now"

**AMOS:** "Your subscription has been cancelled and will end on January 1, 2025. You'll continue to have full access until then. Thank you for your feedback - we've noted that pricing was a concern."

---

## Backend Implementation

### AI Tools Created
All commands are powered by these tools in `app/services/tools/`:

1. `GetBillingInfoTool` - Retrieves subscription and billing details
2. `GetTokenUsageTool` - Shows token usage statistics
3. `UpdateSubscriptionTool` - Changes plan tier
4. `ViewInvoicesTool` - Lists invoice history
5. `CancelSubscriptionTool` - Cancels subscription

### Webhooks
Stripe webhooks automatically update subscription data:
- `customer.subscription.created` - New subscription
- `customer.subscription.updated` - Plan changes
- `customer.subscription.deleted` - Cancellation
- `invoice.payment_succeeded` - Successful payment, resets token usage
- `invoice.payment_failed` - Failed payment
- `customer.subscription.trial_will_end` - Trial ending soon

### Routes
- `POST /stripe/webhooks` - Webhook endpoint
- `POST /stripe/checkout` - Create checkout session
- `POST /stripe/portal` - Access Stripe customer portal
- `GET /stripe/checkout/success` - Post-checkout success
- `GET /stripe/checkout/cancel` - Checkout cancelled

---

## Testing

### Test Cards
Use these cards in test mode:
- `4242 4242 4242 4242` - Success
- `4000 0000 0000 0002` - Card declined
- `4000 0000 0000 9995` - Insufficient funds

### Trigger Test Webhooks
```bash
stripe trigger customer.subscription.created
stripe trigger invoice.payment_succeeded
stripe trigger customer.subscription.trial_will_end
```

---

## Going Live

1. Switch Stripe Dashboard to **Live Mode**
2. Get live API keys from Dashboard
3. Update `.env` with live keys (starts with `sk_live_`)
4. Create live products/prices (same as test mode)
5. Create live webhook endpoint with production URL
6. Test with real payment methods
7. Enable Stripe Radar for fraud protection

---

## Support

If users have issues:
- Direct them to Stripe Customer Portal: `/stripe/portal`
- They can update payment methods there
- They can view full invoice history
- They can download invoices as PDFs
