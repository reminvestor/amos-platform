# Stripe Integration Setup Guide

This guide walks you through setting up Stripe for subscription billing in AMOS.

## 1. API Keys (You Have These ✅)

You've already added:
- ✅ **Secret Key** (`STRIPE_SECRET_KEY`) - Used for server-side API calls
- ✅ **Account ID** - Your Stripe account identifier

### Where to Find These Keys

1. Go to [Stripe Dashboard](https://dashboard.stripe.com/)
2. Click **Developers** → **API keys**
3. Copy your keys:
   - **Test Mode**: Use `sk_test_...` for development
   - **Live Mode**: Use `sk_live_...` for production

## 2. Webhook Secret (Still Needed ⚠️)

The webhook secret (`STRIPE_WEBHOOK_SECRET`) is used to verify that webhook events are genuinely from Stripe.

### For Local Development (Using Stripe CLI)

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Login to your Stripe account
stripe login

# Start forwarding webhooks to your local server
stripe listen --forward-to http://localhost:3000/stripe/webhooks

# The CLI will output your webhook secret (starts with whsec_)
# Copy this secret to your .env file
```

### For Production (Using Stripe Dashboard)

1. Go to [Stripe Dashboard](https://dashboard.stripe.com/)
2. Click **Developers** → **Webhooks**
3. Click **+ Add endpoint**
4. Enter your webhook URL: `https://yourdomain.com/stripe/webhooks`
5. Select events to listen for:
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
   - `customer.subscription.trial_will_end`
6. Click **Add endpoint**
7. Click on the newly created endpoint
8. Click **Reveal** under "Signing secret"
9. Copy the secret (starts with `whsec_`) to your `.env` file

## 3. Price IDs (Still Needed ⚠️)

Price IDs define how much you charge for each subscription tier.

### Create Products and Prices

1. Go to [Stripe Dashboard](https://dashboard.stripe.com/)
2. Click **Product catalog** → **+ Add product**
3. Create three products with prices:

#### Starter Plan
- **Product name**: "Starter Plan"
- **Price**: $29/month (or your preferred amount)
- **Billing period**: Monthly
- **Lookup key**: `starter` (important!)
- Copy the Price ID (starts with `price_`)
- Add to `.env` as `STRIPE_STARTER_PRICE_ID`

#### Professional Plan
- **Product name**: "Professional Plan"
- **Price**: $99/month (or your preferred amount)
- **Billing period**: Monthly
- **Lookup key**: `professional` (important!)
- Copy the Price ID
- Add to `.env` as `STRIPE_PROFESSIONAL_PRICE_ID`

#### Enterprise Plan
- **Product name**: "Enterprise Plan"
- **Price**: $299/month (or your preferred amount)
- **Billing period**: Monthly
- **Lookup key**: `enterprise` (important!)
- Copy the Price ID
- Add to `.env` as `STRIPE_ENTERPRISE_PRICE_ID`

### Set Default Price (Optional)

Set one price as the default for new signups:
- Add to `.env` as `STRIPE_DEFAULT_PRICE_ID`
- Usually this is the same as `STRIPE_STARTER_PRICE_ID`

## 4. Complete .env Configuration

Your `.env` file should look like this:

```bash
# Stripe (for subscription billing)
STRIPE_SECRET_KEY=sk_test_your_secret_key_here
STRIPE_WEBHOOK_SECRET=whsec_your_webhook_secret_here
STRIPE_DEFAULT_PRICE_ID=price_starter_plan_id
STRIPE_STARTER_PRICE_ID=price_starter_plan_id
STRIPE_PROFESSIONAL_PRICE_ID=price_professional_plan_id
STRIPE_ENTERPRISE_PRICE_ID=price_enterprise_plan_id
```

## 5. Testing Your Setup

### Run the Migration

```bash
rails db:migrate
```

### Test Webhook Locally

```bash
# In one terminal, start your Rails server
bin/dev

# In another terminal, start Stripe CLI
stripe listen --forward-to http://localhost:3000/stripe/webhooks

# In a third terminal, trigger a test webhook
stripe trigger customer.subscription.created
```

### Test Checkout Flow

1. Create a checkout session via your app or curl:

```bash
curl -X POST http://localhost:3000/stripe/checkout \
  -H "Content-Type: application/json" \
  -d '{"price_id": "price_your_starter_price_id"}'
```

2. Visit the returned checkout URL
3. Use Stripe test card: `4242 4242 4242 4242`
4. Any future date for expiry
5. Any 3-digit CVC

### Test AI Tools

In your AMOS chat interface, try:
- "What's my billing info?"
- "How many tokens have I used?"
- "Show me my invoices"
- "Upgrade my plan to professional"

## 6. Publishable Key (Optional for Frontend)

If you want to add Stripe Elements (card input) to your frontend:

1. Go to **Developers** → **API keys**
2. Copy your **Publishable key** (starts with `pk_test_` or `pk_live_`)
3. Add to `.env` as `STRIPE_PUBLISHABLE_KEY`

This is **not required** if you're only using Stripe Checkout (which you are).

## 7. What Each Key/ID Does

| Variable | Purpose | Where to Find |
|----------|---------|---------------|
| `STRIPE_SECRET_KEY` | Server-side API authentication | Dashboard → Developers → API keys |
| `STRIPE_WEBHOOK_SECRET` | Verify webhook signatures | Dashboard → Developers → Webhooks → Signing secret |
| `STRIPE_DEFAULT_PRICE_ID` | Default subscription tier | Dashboard → Product catalog → Copy Price ID |
| `STRIPE_STARTER_PRICE_ID` | Starter plan pricing | Dashboard → Product catalog → Copy Price ID |
| `STRIPE_PROFESSIONAL_PRICE_ID` | Professional plan pricing | Dashboard → Product catalog → Copy Price ID |
| `STRIPE_ENTERPRISE_PRICE_ID` | Enterprise plan pricing | Dashboard → Product catalog → Copy Price ID |

## 8. Token Limits

The system automatically sets these token limits per plan:
- **Starter**: 100,000 tokens/month
- **Professional**: 500,000 tokens/month
- **Enterprise**: 2,000,000 tokens/month

Overage charges are calculated at **$0.01 per 1,000 tokens** over the limit.

You can adjust these in the code:
- `app/controllers/stripe_webhooks_controller.rb` (line 131-139)
- `app/controllers/stripe_checkout_controller.rb` (line 96-104)
- `app/services/tools/update_subscription_tool.rb` (line 77-85)

## 9. Going Live

When you're ready for production:

1. **Switch to Live Mode** in Stripe Dashboard
2. **Create live products/prices** (same as test mode)
3. **Create live webhook endpoint** with your production URL
4. **Update .env** with live keys (starts with `sk_live_` and `pk_live_`)
5. **Test thoroughly** with real payment methods
6. **Enable Radar** (Stripe's fraud protection)

## 10. Troubleshooting

### Webhook Not Receiving Events
- Check webhook URL is correct
- Verify webhook secret matches
- Check server logs for errors
- Use Stripe CLI to test locally

### Checkout Session Fails
- Verify price IDs are correct
- Check secret key is valid
- Ensure prices are active in dashboard

### AI Tools Not Working
- Run migration: `rails db:migrate`
- Check entity has `stripe_customer_id` set
- Verify subscription is active

## Next Steps

1. ✅ Add webhook secret to `.env`
2. ✅ Create products and prices in Stripe Dashboard
3. ✅ Add price IDs to `.env`
4. ✅ Run migration: `rails db:migrate`
5. ✅ Test with Stripe CLI and test cards
6. ✅ Build signup/onboarding flow in your app
