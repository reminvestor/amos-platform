# Recipe: Lead Capture Workflow

## Goal
Create a complete lead capture system: Landing Page → Form → Contact → Email Sequence

## Steps

### 1. Create the Landing Page
```
platform_create(type: "landing_page", data: {
  title: "Free Guide: [Topic]",
  description: "Lead capture page for [product/service]"
})
```
Then use `load_canvas(canvas_name: "design_studio")` to design it visually.

### 2. Create a Contact Group for leads
```
platform_create(type: "contact_group", data: {
  name: "Guide Downloads",
  description: "People who downloaded the free guide"
})
```

### 3. Create Welcome Email Template
```
platform_create(type: "email_template", data: {
  name: "Welcome - Guide Download",
  subject: "Here's your free guide, {{first_name}}!",
  body: "<h1>Welcome!</h1><p>Thanks for downloading. Here's your guide...</p>"
})
```

### 4. Create Follow-up Sequence
```
# Create the sequence
platform_create(type: "email_sequence", data: {
  name: "Guide Follow-up",
  goal: "Nurture guide downloaders into customers",
  contact_group_id: <group_id>
})

# Add sequence steps
platform_create(type: "sequence_step", data: {
  email_sequence_id: <sequence_id>,
  step_number: 1,
  delay_hours: 24,
  subject: "Did you enjoy the guide?",
  body: "<p>Hi {{first_name}}, I hope you found the guide helpful...</p>"
})

platform_create(type: "sequence_step", data: {
  email_sequence_id: <sequence_id>,
  step_number: 2,
  delay_hours: 72,
  subject: "Quick question about [topic]",
  body: "<p>I wanted to follow up and see if you had any questions...</p>"
})
```

### 5. Connect Everything
When a contact submits the landing page form:
- Contact is created automatically
- Added to the Contact Group
- Enrolled in the Email Sequence

## Tips
- Keep the landing page focused on ONE thing
- Use a clear CTA (Call to Action)
- Follow up within 24 hours
- 3-5 emails in the sequence is ideal
- Track open rates and adjust
