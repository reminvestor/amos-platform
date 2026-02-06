# Email Campaigns

## Overview
Campaigns send emails to contact groups using email templates.

## Workflow
1. Create an EmailTemplate (the content)
2. Create a Campaign (links template to recipients)
3. Add ContactGroups to the campaign (the recipients)
4. Send the campaign

## Key Fields
- `name` (required)
- `email_template_id` (required for sending)
- `status`: draft, scheduled, sending, sent, cancelled
- `scheduled_at`: when to send (null = immediate)
- `subject`: overrides template subject if set
- `from_email`, `from_name`

## Common Operations

### Create campaign with template
```
# 1. Create the template
platform_create(type: "email_template", data: {
  name: "Summer Sale",
  subject: "Don't miss our summer sale!",
  body: "<h1>Summer Sale</h1><p>Save up to 50%!</p>"
})

# 2. Create the campaign
platform_create(type: "campaign", data: {
  name: "Summer Sale Blast",
  email_template_id: <template_id>
})

# 3. Add recipients
platform_update(type: "campaign", id: <campaign_id>, data: {
  add_contact_group_ids: [1, 2]
})

# 4. Send
platform_execute(action: "send_campaign", campaign_id: <campaign_id>)
```

### Check campaign performance
```
platform_query(type: "campaigns", filters: { status: "sent" }, include: ["metrics"])
```

## Important Notes
- Campaign needs a template AND at least one contact group before sending
- Template variables use {{first_name}}, {{last_name}}, {{email}} (NOT [brackets])
- Once sent, a campaign cannot be sent again
- Use `scheduled_at` for scheduled sends
