# Fixes for Tool Thinking UI and Dynamic Canvas Loading

## Issue 1: Tool Thinking UI
**Problem**: When Scout uses tools, the intermediate thinking steps (like "First, I'll check available Stripe connections", "Now, I'll list the available operations") were being shown as regular chat messages, making the conversation cluttered.

**Solution**: Created a minimalist "tool thinking" UI that:
- Shows tool steps in a separate 3-row window above the chat
- Displays with a progress bar and CPU icon
- Automatically disappears when the actual response starts streaming
- In voice mode, says "One moment, let me work on that for you" instead of reading all steps

### Implementation Details:

1. **New UI Component** (`showToolThinking`, `addToolThinkingStep`, `hideToolThinking`):
   - Creates a dark-themed window with sliding animation
   - Shows up to 3 steps at a time (auto-scrolls)
   - Includes a progress bar animation
   - Fades out smoothly when done

2. **Pattern Detection**:
   - Detects tool thinking patterns like:
     - "First, I'll...", "Now, I'll...", "Next, I'll..."
     - "Let me check/list/execute..."
     - "1. Now, I'll...", "2. Next..."
     - "Checking...", "Retrieving...", "Executing..."

3. **Tool Status Integration**:
   - Shows "Using [tool name]..." when tools are detected
   - Shows "Running [tool name]..." when tools start

## Issue 2: Dynamic Canvas Not Loading
**Problem**: When Scout used the `create_dynamic_visualization` tool, it would say the canvas was created but it wouldn't actually load.

**Solution**: Fixed the canvas loading logic to handle both `canvas:` and `canvas_type:` response keys from the backend.

### Fix Details:
```javascript
// Before: Only checked canvas_type
if (finalResponseData.canvas_type && finalResponseData.canvas_type !== 'conversation')

// After: Checks both keys
const suggestedCanvas = finalResponseData.canvas || finalResponseData.canvas_type
```

## Testing Instructions

1. **Restart your Rails server** to apply all changes

2. **Test Tool Thinking UI**:
   - Ask: "show me my last 10 contacts in Stripe"
   - You should see:
     - Tool thinking window appears with steps like "Checking Stripe connections..."
     - Window disappears when actual contact data starts streaming
     - No tool steps in the main chat

3. **Test Dynamic Canvas**:
   - After Scout shows data, ask: "can you display them on a dynamic canvas"
   - The dynamic visualization should load immediately

4. **Test Voice Mode**:
   - Enable voice mode
   - Ask Scout to use tools
   - Should hear: "One moment, let me work on that for you"
   - Tool steps should NOT be read aloud

## Visual Design

The tool thinking UI uses:
- Dark background matching Scout's theme
- Minimal height (120px max)
- Sliding animation for smooth appearance
- Progress bar showing activity
- CPU icon indicating processing
- Auto-fade after 300ms when done

## Benefits

1. **Cleaner Conversations**: Tool steps no longer clutter the chat
2. **Better UX**: Users see Scout is working without verbose details
3. **Voice Mode Friendly**: No more reading technical steps aloud
4. **Canvas Loading Fixed**: Dynamic visualizations work as expected
