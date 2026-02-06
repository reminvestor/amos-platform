# Contacts & CRM

## Overview
Contacts are the core of the platform's CRM. Every person the organization interacts with is a Contact.

## Key Fields
- `email` (required, unique per entity)
- `first_name`, `last_name`
- `status`: active, inactive, unsubscribed, bounced
- `lifecycle_stage`: subscriber, lead, mql, sql, opportunity, customer, evangelist, other
- `lead`: boolean (is this a lead?)
- `phone`, `company`, `title`, `address`, `city`, `state`, `zip`, `country`
- `source`: where the contact came from
- `tags`: array of tags
- `custom_fields`: JSON for additional data

## Relationships
- Contact → ContactGroups (many-to-many, for segmentation)
- Contact → Opportunities (one-to-many, sales pipeline)
- Contact → Activities (one-to-many, interaction history)
- Contact → EmailDeliveries (one-to-many, email history)
- Contact → SequenceEnrollments (one-to-many, automation)

## Common Operations

### Query contacts
```
platform_query(type: "contacts", filters: { status: "active" }, limit: 20)
platform_query(type: "contacts", search: "john@example.com")
platform_query(type: "contacts", filters: { lifecycle_stage: "customer" })
```

### Create a contact
```
platform_create(type: "contact", data: {
  email: "jane@example.com",
  first_name: "Jane",
  last_name: "Doe",
  status: "active",
  lead: true
})
```

### Update a contact
```
platform_update(type: "contact", id: 42, data: { lifecycle_stage: "customer" })
```

### Add to group
```
platform_update(type: "contact", id: 42, data: { contact_group_ids: [1, 2] })
```

## Important Notes
- Status must be lowercase: active, inactive, unsubscribed, bounced
- Don't confuse `status` (subscription state) with `lifecycle_stage` (sales funnel position)
- `lead: true` marks the contact as a sales lead
- Email is unique per entity — duplicates will fail validation
