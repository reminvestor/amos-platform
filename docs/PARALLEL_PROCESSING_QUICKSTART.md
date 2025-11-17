# Parallel Processing Quick Start

## Test Now!

Try these messages in Scout chat to see parallel processing in action:

### 1. **Simple Parallel Request** ✅
```
"Pull my top 10 customers from Stripe and also give me an overview of contacts"
```
- ✅ Triggers parallel processing
- ✅ Shows parallel tasks panel
- ✅ Executes Stripe & contacts queries simultaneously

### 2. **Analysis + Action** ✅
```
"Analyze my campaigns and also schedule a meeting with my team"
```
- Parallel tasks: Campaign analysis + Calendar check
- Real-time progress updates

### 3. **Multiple File Processing** ✅
Upload 2+ files and say:
```
"Analyze these documents"
```
- Each file processed in parallel
- Progress bar for each

## Visual Indicators

When parallel processing activates:

1. **Chat shows**: "🚀 **Activating parallel processing**..."
2. **Panel slides in** from right side
3. **Real-time progress** for each task
4. **Results stream** as tasks complete

## Troubleshooting

### "Not seeing parallel processing?"

Check the logs for:
```
🚀 Parallel processing triggered for: [your message]
```

Or:
```
🔄 Sequential processing for: [your message]  
```

### Common Triggers

Your message needs one of these patterns:
- "X **and also** Y"  
- "X **and** Y"
- "**both** X and Y"
- Multiple questions: "What is X? Can you also Y?"
- Action lists: "First do X, then Y"

### Demo Commands

```bash
# Run the demo (make sure foreman is running first!)
rails parallel:demo

# Clean up demo tasks
rails parallel:cleanup
```

### Admin Dashboard

Monitor all parallel tasks at:
```
/admin/parallel_tasks
```

## Quick Debug

Add to any message to force parallel:
- "Can you do X and also do Y?" 
- "Pull X and show me Y"
- "First analyze X, then create Y"

The key is using conjunctions (and, also, then) or listing multiple distinct actions!
