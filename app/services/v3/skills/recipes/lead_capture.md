# Recipe: Lead Capture Workflow

## Goal
Create a complete lead capture system: Landing Page → Form → Contact → Email Sequence

## Steps

### 1. Create the Landing Page
Use the platform_create tool with type: "landing_page", data: { title: "Free Guide: [Topic]", description: "Lead capture page for [product/service]" }

Then use the load_canvas tool with canvas_name: "landing_page_editor" and canvas_data: { landing_page_id: ID } to edit it visually.

### 2. Create a Contact Group for leads
Use the platform_create tool with type: "contact_group", data: { name: "Guide Downloads", description: "People who downloaded the free guide" }

### 3. Create Welcome Email Template
Use the platform_create tool with type: "email_template", data: { name: "Welcome - Guide Download", subject: "Here's your free guide, {{first_name}}!", body: "<h1>Welcome!</h1><p>Thanks for downloading. Here's your guide...</p>" }

### 4. Create Follow-up Sequence
Step 1: Use the platform_create tool with type: "email_sequence", data: { name: "Guide Follow-up", goal: "Nurture guide downloaders into customers", contact_group_id: <group_id> }

Step 2: Use the platform_create tool with type: "sequence_step", data: { email_sequence_id: <sequence_id>, step_number: 1, delay_hours: 24, subject: "Did you enjoy the guide?", body: "<p>Hi {{first_name}}, I hope you found the guide helpful...</p>" }

Step 3: Use the platform_create tool with type: "sequence_step", data: { email_sequence_id: <sequence_id>, step_number: 2, delay_hours: 72, subject: "Quick question about [topic]", body: "<p>I wanted to follow up and see if you had any questions...</p>" }

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
