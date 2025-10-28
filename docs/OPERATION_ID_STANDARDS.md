# Integration Operation ID Standards

## Format
All `operation_id` values must follow this format:
```
{integration_slug}.{operation_name}
```

## Examples
✅ **Correct:**
- `stripe.list_customers`
- `quickbooks.get_company_info`
- `shopify.list_products`

❌ **Wrong:**
- `stripe.list_customers.v2020-08-27` (no version suffixes)
- `quickbooks.get_company_info.v3` (no version suffixes)
- `list_customers` (missing slug prefix)

## Rationale
1. **Simplicity**: Easy for AI and developers to understand
2. **Consistency**: All integrations follow the same pattern
3. **Scalability**: No need for regex matching or version management
4. **Maintainability**: Clean, predictable naming convention

## Migration
Run `rails db:migrate` to normalize all existing operation_ids to this format.

## Future Operations
When creating new operations (via seeds, admin UI, or AI builder), always use the format:
```ruby
operation_id: "#{integration.slug}.#{operation_name}"
```

