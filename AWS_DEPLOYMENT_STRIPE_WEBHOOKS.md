# AWS Deployment - Stripe Webhook Configuration

## Webhook URL for Production

Once deployed to AWS, you'll need to configure Stripe webhooks to point to your production URL.

### Webhook Endpoint

**URL Format:** `https://your-domain.com/stripe/webhooks`

**Example URLs:**
- `https://app.amos-labs.com/stripe/webhooks`
- `https://yourdomain.com/stripe/webhooks`

### Events to Subscribe To

Configure these webhook events in Stripe Dashboard:

**Required Events:**
1. `customer.subscription.created` - New subscription created
2. `customer.subscription.updated` - Subscription plan changed
3. `customer.subscription.deleted` - Subscription cancelled
4. `invoice.payment_succeeded` - Successful payment (token reset)
5. `invoice.payment_failed` - Failed payment (mark account past_due)
6. `customer.subscription.trial_will_end` - Trial ending soon

### Setup Steps

#### 1. Get Your Production URL

After AWS deployment, your app will be at:
```
https://your-domain.com
```

The webhook endpoint will be:
```
https://your-domain.com/stripe/webhooks
```

#### 2. Create Webhook Endpoint in Stripe

1. Go to [Stripe Dashboard](https://dashboard.stripe.com)
2. Click **Developers** → **Webhooks**
3. Click **Add endpoint**
4. Enter your webhook URL: `https://your-domain.com/stripe/webhooks`
5. Select events to listen to (see list above)
6. Click **Add endpoint**

#### 3. Get Webhook Signing Secret

After creating the endpoint:
1. Click on your new webhook endpoint
2. Click **Reveal** under "Signing secret"
3. Copy the secret (starts with `whsec_`)

#### 4. Add to AWS Environment Variables

Add the webhook secret to your AWS deployment environment variables:

```bash
STRIPE_WEBHOOK_SECRET=whsec_your_production_webhook_secret_here
```

**Where to set this:**
- AWS Elastic Beanstalk: Configuration → Software → Environment properties
- AWS ECS: Task Definition → Environment variables
- AWS Lambda: Configuration → Environment variables
- AWS App Runner: Configuration → Environment variables

### Verification

#### Test Webhook in Stripe Dashboard

1. Go to **Developers** → **Webhooks**
2. Click your webhook endpoint
3. Click **Send test webhook**
4. Select an event type (e.g., `customer.subscription.created`)
5. Click **Send test webhook**
6. Check the response - should see **200 OK**

#### Check Application Logs

After sending test webhook, check your AWS logs:
```
Subscription created for entity [ID]
```

### What Gets Logged

Every webhook event creates a `SubscriptionEvent` record:

```ruby
# Check in Rails console
entity = Entity.find_by(stripe_customer_id: 'cus_xxx')
entity.print_subscription_history
```

See [SUBSCRIPTION_TRACKING.md](SUBSCRIPTION_TRACKING.md) for details.

### Troubleshooting

#### Webhook Shows Failed (Non-200 Response)

1. **Check webhook secret**
   - Ensure `STRIPE_WEBHOOK_SECRET` environment variable is set correctly in AWS
   - Secret should start with `whsec_`

2. **Check application logs**
   - Look for `Stripe webhook signature verification failed`
   - Look for `Stripe webhook JSON parse error`

3. **Verify URL is accessible**
   ```bash
   curl -I https://your-domain.com/stripe/webhooks
   # Should return: 405 Method Not Allowed (GET not allowed, POST required)
   ```

#### Subscription Not Updating

1. **Check webhook is enabled**
   - Go to Stripe Dashboard → Webhooks
   - Ensure endpoint is **Enabled** (not disabled)

2. **Check webhook events**
   - Click on webhook endpoint
   - Review **Attempts** tab for errors

3. **Check database**
   ```ruby
   # Rails console
   SubscriptionEvent.recent.limit(10)
   # Should see recent webhook events
   ```

#### Duplicate Events

The app automatically handles duplicate webhook events using `stripe_event_id` uniqueness constraint. Stripe may send the same webhook multiple times, but only the first one will be processed.

### Security Notes

- ✅ Webhook signature verification is enabled (prevents fake webhooks)
- ✅ HTTPS required (Stripe only sends to HTTPS endpoints)
- ✅ Duplicate event prevention (via unique stripe_event_id)
- ✅ Error handling (logs errors without crashing)

### Environment Variables Checklist

Before going live, ensure these are set in AWS:

```bash
# Required
STRIPE_SECRET_KEY=sk_live_...           # Live secret key (not test key!)
STRIPE_WEBHOOK_SECRET=whsec_...         # Webhook signing secret

# For checkout (if using)
STRIPE_STARTER_PRICE_ID=price_...       # Starter plan price ID
STRIPE_PROFESSIONAL_PRICE_ID=price_...  # Professional plan price ID
STRIPE_BUSINESS_PRICE_ID=price_...      # Business plan price ID
STRIPE_ENTERPRISE_PRICE_ID=price_...    # Enterprise plan price ID
```

### Testing Production Webhooks

#### Safe Test (Recommended)

Use Stripe test mode:
1. Create a separate webhook endpoint for test mode
2. Use test API keys
3. Test subscription flow end-to-end
4. Verify events are logged correctly

#### Live Test (Caution)

Only after thoroughly testing in test mode:
1. Create a real subscription ($0.00 trial is safe)
2. Monitor webhook delivery in Stripe Dashboard
3. Check `SubscriptionEvent` records are created
4. Cancel the subscription immediately if needed

### Post-Deployment Checklist

- [ ] Production URL deployed and accessible
- [ ] Webhook endpoint created in Stripe
- [ ] Webhook signing secret added to AWS environment variables
- [ ] Test webhook sent successfully (200 OK response)
- [ ] Test subscription created and webhook received
- [ ] SubscriptionEvent records being created
- [ ] Application logs show successful webhook processing
- [ ] Switch from test keys to live keys
- [ ] Monitor first few real subscriptions

### Support

If webhook delivery fails:
1. Check Stripe Dashboard → Webhooks → [Your endpoint] → Attempts
2. Review error messages
3. Check AWS application logs
4. Verify environment variables are set correctly
5. Test with `stripe listen` locally first

See also:
- [STRIPE_SETUP_GUIDE.md](docs/STRIPE_SETUP_GUIDE.md) - Local development setup
- [SUBSCRIPTION_TRACKING.md](SUBSCRIPTION_TRACKING.md) - Event tracking details
- [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md) - Development environment
