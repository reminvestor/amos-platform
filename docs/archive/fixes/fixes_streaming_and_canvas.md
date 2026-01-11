# Fixes Applied for Streaming and Canvas Loading Issues

## Issue 1: Messages Not Streaming
**Problem**: Messages were loading all at once instead of streaming character by character.

**Root Cause**: The orchestrator wasn't properly accumulating the response when handling streaming chunks.

**Fix Applied**: 
- Modified `app/services/amos/orchestrator.rb` to properly initialize `accumulated_response` as an empty string
- Ensured text chunks are properly extracted and accumulated during streaming
- Fixed the chunk handling to properly identify text content vs other chunk types

## Issue 2: Canvas Not Loading
**Problem**: Scout said it loaded the email campaign canvas but it didn't actually load.

**Root Causes**:
1. Canvas updates weren't being passed through the streaming pipeline
2. The `load_canvas` tool definition was missing some canvas types
3. The tool didn't support passing canvas data (like campaign_id)

**Fixes Applied**:

1. **Updated SimpleQueryHandler** (`app/services/amos/simple_query_handler.rb`):
   - Added handling for `canvas_update` chunks in `process_with_tools_streaming`
   - Now properly passes canvas updates through to the orchestrator

2. **Updated Orchestrator** (`app/services/amos/orchestrator.rb`):
   - Added handling for canvas update chunks during streaming
   - Broadcasts canvas updates via ScoutChannel with proper `load_canvas` type
   - Added logging for canvas updates

3. **Updated Tool Catalog** (`app/services/tools/tool_catalog.rb`):
   - Added missing canvas types: `email_campaign_viewer`, `parallel_tasks`, `landing_page_editor`
   - Added `canvas_data` parameter to support passing data like campaign_id or landing_page_id
   - Made canvas_data optional but allows additional properties

## Testing Instructions

1. **Restart your server** to apply all changes

2. **Test Streaming**:
   - Send a simple message to Scout
   - You should see the response stream in character by character, not all at once

3. **Test Canvas Loading**:
   - Ask Scout to "show email campaigns"
   - Scout should retrieve the campaigns AND load the email campaign viewer canvas
   - The canvas should actually load in the UI

4. **Test with Different Canvases**:
   - Try loading other canvases like "show landing pages" or "show analytics"
   - Each should both describe the content AND load the appropriate canvas

## Technical Details

The streaming fix ensures that:
- Text chunks are properly identified and broadcast with `streaming: true` metadata
- The accumulated response is built correctly for context storage
- Canvas updates bypass the text streaming and go directly to ScoutChannel

The canvas loading fix ensures that:
- Scout can use the `load_canvas` tool with any of the defined canvas types
- Canvas data (IDs, filters, etc.) can be passed to the canvas when loading
- Canvas updates are properly broadcast and handled by the frontend
