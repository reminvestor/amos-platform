# Stripe Integration Expert Knowledge

## Overview
Stripe is a payment processing platform. This document contains expert knowledge for interacting with the Stripe API.

## Authentication
- **Type**: Basic Auth (API Key as username, empty password)
- **Header**: `Authorization: Basic base64(sk_key:)`
- **Keys**: Use `sk_test_*` for sandbox, `sk_live_*` for production

## API Base URL
- **Production/Test**: https://api.stripe.com

## Stripe API Patterns

### Pagination
Stripe uses **cursor-based pagination** with `starting_after` and `ending_before` parameters.

```
GET /v1/customers?limit=10&starting_after=cus_xxx
```

**Pagination Parameters**:
- `limit`: Number of objects to return (1-100, default: 10)
- `starting_after`: Object ID for forward pagination
- `ending_before`: Object ID for backward pagination

### Date Filtering
Stripe uses Unix timestamps and nested parameters for date filters.

```
GET /v1/customers?created[gte]=1704067200&created[lte]=1706745600
```

**Date Filter Keys**:
- `created[gt]`: Created after timestamp
- `created[gte]`: Created at or after timestamp
- `created[lt]`: Created before timestamp
- `created[lte]`: Created at or before timestamp

## Common Operations

### List Customers
```
GET /v1/customers
```
**Parameters**:
- `limit`: 1-100 (default: 10)
- `email`: Filter by exact email
- `starting_after`: Cursor for pagination
- `created[gte]`, `created[lte]`: Date filters

### Create Customer
```
POST /v1/customers
```
**Body**:
```json
{
  "email": "customer@example.com",
  "name": "John Doe",
  "phone": "+1234567890",
  "metadata": {
    "custom_field": "value"
  }
}
```

### List Invoices
```
GET /v1/invoices
```
**Parameters**:
- `customer`: Filter by customer ID
- `status`: `draft`, `open`, `paid`, `uncollectible`, `void`
- `collection_method`: `charge_automatically`, `send_invoice`
- `due_date`: Unix timestamp filter

### Create Invoice
```
POST /v1/invoices
```
**Body**:
```json
{
  "customer": "cus_xxx",
  "auto_advance": true,
  "collection_method": "send_invoice",
  "days_until_due": 30
}
```

### List Subscriptions
```
GET /v1/subscriptions
```
**Parameters**:
- `customer`: Filter by customer ID
- `price`: Filter by price ID
- `status`: `active`, `past_due`, `canceled`, `trialing`, etc.

### Create Subscription
```
POST /v1/subscriptions
```
**Body**:
```json
{
  "customer": "cus_xxx",
  "items": [
    {"price": "price_xxx"}
  ]
}
```

### List Payments (Payment Intents)
```
GET /v1/payment_intents
```
**Parameters**:
- `customer`: Filter by customer ID
- `created[gte]`, `created[lte]`: Date filters

### List Charges
```
GET /v1/charges
```
**Parameters**:
- `customer`: Filter by customer ID
- `payment_intent`: Filter by payment intent ID

## Status Values

### Invoice Statuses
- `draft`: Invoice not finalized yet
- `open`: Invoice is finalized and awaiting payment
- `paid`: Invoice has been paid
- `uncollectible`: Invoice's payment has failed or is being disputed
- `void`: Invoice was voided

### Subscription Statuses
- `active`: Subscription is active
- `past_due`: Payment failed but subscription still active
- `canceled`: Subscription was canceled
- `trialing`: In trial period
- `incomplete`: Awaiting first payment
- `incomplete_expired`: First payment failed

### Payment Intent Statuses
- `requires_payment_method`: Payment method needed
- `requires_confirmation`: Needs confirmation
- `requires_action`: 3D Secure or similar needed
- `processing`: Payment is processing
- `succeeded`: Payment completed
- `canceled`: Payment was canceled

## Error Handling

### Common Error Types
- `card_error`: Card was declined
- `rate_limit_error`: Too many requests
- `invalid_request_error`: Invalid parameters
- `authentication_error`: Invalid API key
- `api_connection_error`: Network issues

### Rate Limits
- **Default**: 100 requests per second (test mode: 25/sec)
- **Bulk operations**: Use batch endpoints when possible

## Best Practices

### For Listing Data
1. Always specify a reasonable `limit` (10-100)
2. Use `starting_after` for pagination
3. Filter by date range to limit results
4. Use specific status filters when looking for open invoices

### For Creating Records
1. Validate customer exists before creating invoices
2. Use idempotency keys for retries: `Idempotency-Key: unique_string`
3. Handle webhook events for async operations

### Metadata
Stripe objects support `metadata` field for custom key-value pairs:
```json
{
  "metadata": {
    "order_id": "12345",
    "source": "crm"
  }
}
```

## Parameter Mapping Reference

When Amos or users request common operations, translate to Stripe parameters:

| User Request | Stripe Parameters |
|-------------|-------------------|
| "All customers" | GET /v1/customers?limit=100 |
| "Open invoices" | GET /v1/invoices?status=open |
| "Paid invoices" | GET /v1/invoices?status=paid |
| "Active subscriptions" | GET /v1/subscriptions?status=active |
| "Payments this month" | GET /v1/payment_intents?created[gte]={month_start_timestamp} |
| "Customer by email" | GET /v1/customers?email=xxx@example.com |
| "Limit to 50" | Add limit=50 |
| "Next page" | Add starting_after={last_object_id} |

## Integration Operations Available

### list_customers (stripe.list_customers)
- Path: /v1/customers
- Method: GET
- Params: limit, email, starting_after, created[gte], created[lte]

### create_customer (stripe.create_customer)
- Path: /v1/customers
- Method: POST
- Body: email, name, phone, metadata

### list_invoices (stripe.list_invoices)
- Path: /v1/invoices
- Method: GET
- Params: customer, status, limit, starting_after

### create_invoice (stripe.create_invoice)
- Path: /v1/invoices
- Method: POST
- Body: customer, auto_advance, collection_method, days_until_due

### list_subscriptions (stripe.list_subscriptions)
- Path: /v1/subscriptions
- Method: GET
- Params: customer, price, status, limit

### list_payments (stripe.list_payment_intents)
- Path: /v1/payment_intents
- Method: GET
- Params: customer, created[gte], limit

## Troubleshooting Checklist

1. ✅ Is the API key valid and for the correct mode (test/live)?
2. ✅ Are timestamps in Unix format (seconds since epoch)?
3. ✅ For pagination, is `starting_after` a valid object ID?
4. ✅ Are nested parameters properly formatted (e.g., `created[gte]`)?
5. ✅ For customer operations, does the customer ID exist?
6. ✅ Is idempotency key included for POST requests?

---
*This documentation is maintained for use by the Stripe integration agent and Amos orchestrator. Last updated: January 2026.*

