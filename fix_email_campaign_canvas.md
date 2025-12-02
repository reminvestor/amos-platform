# Fix for Email Campaign Canvas Not Displaying

## Problem
When Scout attempted to load the email campaign viewer:
1. The canvas would briefly "blink" (indicating it tried to load)
2. But would immediately revert to the default/main canvas
3. The logs showed the canvas loaded successfully (200 status, HTML content received)
4. But the title was empty, suggesting a missing case

## Root Cause
The Scout controller's `load_canvas` method didn't have a case for `"email_campaign_viewer"`. When an unrecognized canvas type is requested, it falls through to the default case which renders an empty canvas with no title.

## Fix Applied
Updated `/app/controllers/scout_controller.rb` to handle both `"campaign_viewer"` and `"email_campaign_viewer"`:

```ruby
when "campaign_viewer", "email_campaign_viewer"
  canvas_content = render_campaign_canvas(canvas_data)
  canvas_title = "Email Campaigns"
```

## Why This Happened
1. The tool catalog was updated to use `"email_campaign_viewer"` as the canvas name
2. But the backend controller only recognized `"campaign_viewer"`
3. This mismatch caused the canvas to fail to load properly

## Testing Instructions
1. Restart your Rails server
2. Try these commands:
   - "show me my email campaigns"
   - "tell me about my recent email campaigns"
   - "how are my email campaigns doing?"

Each should now:
- Immediately load the email campaigns canvas
- Display your campaigns with the title "Email Campaigns"
- The canvas should stay visible (not revert to default)

## Additional Notes
- The canvas was loading successfully (11,379 characters of HTML)
- But without a matching case, it rendered the default empty canvas
- This fix ensures both "campaign_viewer" and "email_campaign_viewer" work
