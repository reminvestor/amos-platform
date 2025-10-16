# Stripe Subscription Signup Flow

## Complete User Journey

### 1. User Signs Up
**Route:** `/users/sign_up`

**What Happens:**
- User fills in: email, password, full name, business name
- `RegistrationsController#create` creates:
  - New Entity (business)
  - New User (owner)
  - EntityUser association (role: owner)
- Redirects to → **Plan Selection**

---

### 2. Plan Selection
**Route:** `/subscriptions/new`

**What User Sees:**
- Three plan cards:
  - **Starter**: $29/month, 200k tokens
  - **Professional**: $119/month, 1M tokens (Most Popular)
  - **Business**: $299/month, 2M tokens
- "Start 7-Day Trial" buttons
- Note: "No credit card required until trial ends" ❌ **Actually collects CC immediately**

**What Happens:**
- User clicks button → `POST /subscriptions`
- `SubscriptionsController#create`:
  - Creates Stripe Customer (if doesn't exist)
  - Creates Stripe Checkout Session with:
    - Selected price ID
    - 7-day trial period
    - Collects payment method immediately
  - Redirects to → **Stripe Checkout**

---

### 3. Stripe Checkout
**Route:** `https://checkout.stripe.com/...` (external)

**What User Sees:**
- Stripe's secure payment form
- Enter credit card details
- Billing address
- Apply promo codes (optional)

**What Happens:**
- User enters payment info
- Stripe validates card
- Creates subscription in "trialing" status
- Redirects to → **Success Page**

---

### 4. Checkout Success
**Route:** `/subscriptions/success?session_id=...`

**What Happens:**
- `SubscriptionsController#success`:
  - Retrieves Stripe session & subscription
  - Updates Entity with:
    - `stripe_subscription_id`
    - `subscription_status`: "trialing"
    - `trial_ends_at`: 7 days from now
    - `plan_tier`: starter/professional/business
    - `token_limit`: 200k/1M/2M
- Redirects to → **Onboarding Chat**

---

### 5. Onboarding Chat Wizard
**Route:** `/onboarding`

**What User Sees:**
- AI-powered conversational onboarding
- Questions about business, goals, etc.
- Sets up initial data

**What Happens:**
- `OnboardingController` manages chat
- User completes onboarding
- `user.update(onboarded: true)`
- Redirects to → **Main Chat/Dashboard**

---

### 6. Main Application
**Route:** `/chat` or `/`

**User Has Full Access:**
- All features unlocked during trial
- Token usage tracked
- 7 days until first charge

---

## Subscription States

| Status | Meaning | User Access |
|--------|---------|-------------|
| `trialing` | In 7-day free trial | ✅ Full access |
| `active` | Paid subscription | ✅ Full access |
| `past_due` | Payment failed | ⚠️ Limited access |
| `cancelled` | User cancelled | ❌ Access until period end |
| `incomplete` | Checkout not completed | ❌ No access |

---

## Webhooks (Background Processing)

### After Stripe Checkout
**Event:** `customer.subscription.created`
- Stripe → `/stripe/webhooks`
- `StripeWebhooksController#handle_subscription_created`
- Updates Entity with subscription details

### When Trial Ends (Day 7)
**Event:** `invoice.payment_succeeded`
- Stripe charges the card
- Stripe → `/stripe/webhooks`
- `StripeWebhooksController#handle_invoice_payment_succeeded`
- Updates: `subscription_status = 'active'`
- Resets: `token_usage = 0` (new billing period)

### If Payment Fails
**Event:** `invoice.payment_failed`
- Stripe → `/stripe/webhooks`
- `StripeWebhooksController#handle_invoice_payment_failed`
- Updates: `subscription_status = 'past_due'`
- TODO: Send notification email

### 3 Days Before Trial Ends
**Event:** `customer.subscription.trial_will_end`
- Stripe → `/stripe/webhooks`
- `StripeWebhooksController#handle_trial_will_end`
- TODO: Send reminder email

---

## Access Control

### Application Controller
`check_subscription_status` runs before every request:

```ruby
if subscription_status NOT in ['active', 'trialing']
  redirect_to new_subscription_path
end
```

**Exceptions (Allowed):**
- Subscription pages
- Stripe webhooks
- Stripe checkout pages
- API endpoints
- Devise pages (login/logout)

---

## Token Usage & Overage

### During Each Billing Period
- Tokens consumed increment `entity.token_usage`
- Limit based on plan tier
- User can check in chat: "How many tokens have I used?"

### End of Billing Period
- Webhook: `invoice.payment_succeeded`
- Code resets: `entity.token_usage = 0`

### Overage Charges
- If `token_usage > token_limit`:
  - Calculate: `(overage_tokens / 1000) * $0.01`
  - Stripe automatically bills on next invoice
- User sees warning in chat at 70% and 90%

---

## Chat Commands (Post-Signup)

Once subscribed, users can manage via chat:

| Command | Tool | Example |
|---------|------|---------|
| Check billing | `GetBillingInfoTool` | "What's my billing info?" |
| Check usage | `GetTokenUsageTool` | "How many tokens have I used?" |
| Upgrade plan | `UpdateSubscriptionTool` | "Upgrade to professional" |
| View invoices | `ViewInvoicesTool` | "Show my invoices" |
| Cancel sub | `CancelSubscriptionTool` | "Cancel my subscription" |

---

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ 1. SIGNUP                                                   │
│    /users/sign_up                                           │
│    → Create Entity + User                                   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. PLAN SELECTION                                           │
│    /subscriptions/new                                       │
│    → Choose: Starter / Pro / Business                       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. STRIPE CHECKOUT (External)                               │
│    checkout.stripe.com/...                                  │
│    → Enter credit card                                      │
│    → 7-day trial starts                                     │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. SUCCESS                                                  │
│    /subscriptions/success                                   │
│    → Update subscription_status = "trialing"                │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. ONBOARDING CHAT                                          │
│    /onboarding                                              │
│    → AI guides setup                                        │
│    → onboarded = true                                       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. MAIN APP                                                 │
│    /chat                                                    │
│    → Full access (trial or active)                          │
│    → Track token usage                                      │
└─────────────────────────────────────────────────────────────┘

                    AFTER 7 DAYS
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ WEBHOOK: invoice.payment_succeeded                          │
│    → Stripe charges card                                    │
│    → subscription_status = "active"                         │
│    → token_usage = 0 (new period)                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Testing the Flow

### 1. Sign Up New User
```
Go to: http://localhost:3000/users/sign_up
Enter: email, password, name, business name
```

### 2. Should Redirect to Plan Selection
```
URL: /subscriptions/new
See: 3 plan cards
```

### 3. Click "Start 7-Day Trial" (Starter)
```
Should redirect to Stripe Checkout
Use test card: 4242 4242 4242 4242
```

### 4. After Payment
```
Should redirect to: /subscriptions/success
Then to: /onboarding
```

### 5. Complete Onboarding
```
Chat with AI to complete setup
Should redirect to: /chat
```

### 6. Test Subscription Check
```
Try accessing /campaigns
Should work (subscription active)
```

### 7. Test Token Usage in Chat
```
Say: "How many tokens have I used?"
Should show: usage, limit, percentage
```

---

## Environment Variables Needed

```bash
# Stripe API Keys
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

# Price IDs (from Stripe Dashboard)
STRIPE_DEFAULT_PRICE_ID=price_...
STRIPE_STARTER_PRICE_ID=price_...
STRIPE_PROFESSIONAL_PRICE_ID=price_...
STRIPE_BUSINESS_PRICE_ID=price_...
```

---

## Going Live Checklist

- [ ] Switch to live Stripe keys
- [ ] Create live products/prices in Stripe
- [ ] Update .env with live price IDs
- [ ] Create live webhook endpoint
- [ ] Test real payment end-to-end
- [ ] Enable Stripe Radar (fraud protection)
- [ ] Set up email notifications (trial ending, payment failed)
- [ ] Update pricing page to match Stripe prices
- [ ] Add terms & conditions link
- [ ] Add refund policy

---

## Troubleshooting

### "Please select a plan to continue" Loop
- Entity `subscription_status` is not 'active' or 'trialing'
- Check: `Entity.find(X).subscription_status`
- Fix: Update manually or complete checkout

### Webhooks Not Firing
- Stripe CLI not running (`stripe listen`)
- Wrong webhook secret in .env
- Check Stripe Dashboard → Webhooks → Logs

### Credit Card Declined in Test
- Use test cards: https://stripe.com/docs/testing
- 4242 4242 4242 4242 (success)
- 4000 0000 0000 0002 (decline)

### Token Usage Not Resetting
- Webhook `invoice.payment_succeeded` not firing
- Check webhook logs
- Billing reason must be 'subscription_cycle'
