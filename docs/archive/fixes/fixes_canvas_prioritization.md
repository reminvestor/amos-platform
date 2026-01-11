# Canvas Loading Prioritization Fixes

## Problem
Scout was being too conversational when users clearly wanted to SEE data. Examples:
- "tell me about my email campaigns" → Scout would describe them instead of showing
- "can you load them for me?" → Scout would ask for clarification
- Only explicitly asking "show me my email campaigns" would actually load the canvas

## Root Cause
The system was not prioritizing visual display (canvases) over conversational responses. Scout would default to talking about things instead of showing them.

## Fixes Applied

### 1. Enhanced Pattern Recognition (`app/services/amos/simple_query_handler.rb`)
Added comprehensive patterns to detect when users want to see something:
- Direct patterns: "show", "view", "display", "load", "open", "see"
- Contextual patterns: "load them for me", "show them", "tell me about my X"
- Implicit patterns: References to "them/those/these" after discussing data

### 2. Updated System Prompts

#### ScoutGenericToolsServiceV2 (`app/services/scout_generic_tools_service_v2.rb`)
Added a CRITICAL section emphasizing "SHOW DON'T TELL":
- Clear priority: Load canvas FIRST, then provide insights
- Specific mappings for common requests
- Examples of right vs wrong behavior

#### SimpleQueryHandler (`app/services/amos/simple_query_handler.rb`)
Updated to clarify that simple chat handler should NOT handle view/show requests:
- Those require the tools handler
- Prevents fallback to conversational responses

### 3. Tool Catalog Updates (`app/services/tools/tool_catalog.rb`)
- Added missing canvas types: `email_campaign_viewer`
- Added optional `canvas_data` parameter for passing IDs/filters

## Expected Behavior After Fix

### Before:
```
User: "tell me about my recent email campaigns"
Scout: "I'd be happy to help you review your campaigns. What details are you interested in?"
User: "can you just load them for me?"
Scout: "Could you clarify what you want me to load?"
User: "show me my email campaigns"
Scout: [Finally loads canvas]
```

### After:
```
User: "tell me about my recent email campaigns"
Scout: [Immediately loads email campaign viewer canvas] "I've loaded your email campaigns. You can see..."
```

## Design Pattern
The new prioritization follows this pattern:
1. **Canvas Loading**: Use existing UI canvases to show data visually
2. **Tool Usage**: Fetch additional data if needed
3. **Agent Delegation**: Only for complex creation/modification tasks

This ensures users see their data immediately rather than having to ask multiple times.

## Testing Instructions
1. Restart the server
2. Try variations of viewing requests:
   - "tell me about my email campaigns"
   - "show me campaigns"
   - "can you load them"
   - "what landing pages do I have"
   
Each should immediately load the appropriate canvas without asking for clarification.
