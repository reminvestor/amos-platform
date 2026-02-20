# 🎬 Giphy API Setup Guide

## Quick Setup (5 minutes)

The Giphy public beta key is no longer available, so you'll need your own free API key.

### Step 1: Get Your Free Giphy API Key

1. **Go to**: https://developers.giphy.com/
2. **Click**: "Create an App"
3. **Sign up** (free, no credit card required)
4. **Create SDK App** (not API app):
   - Name: "AMOS Team Space"
   - Description: "GIF sharing in team collaboration"
5. **Copy your API Key** (looks like: `AbCdEf1234567890GhIjKl`)

---

### Step 2: Add Key to Rails Credentials

**Open your credentials:**
```bash
EDITOR="code --wait" bin/rails credentials:edit
```

**Add this to the file:**
```yaml
giphy:
  api_key: YOUR_API_KEY_HERE
```

**Save and close** the editor.

---

### Step 3: Restart Your Server

```bash
# If using Docker:
podman compose restart web

# If using bin/dev:
# Press Ctrl+C to stop
bin/dev

# If using rails s:
# Press Ctrl+C to stop
rails s
```

---

### Step 4: Test It!

1. Refresh your browser
2. Go to Team Space
3. Click the GIF button (🖼️)
4. Search for "excited"
5. GIFs should load!

---

## Alternative: Disable GIF Button

If you don't want to use GIFs, you can hide the button:

**Add to your CSS:**
```css
.gif-btn {
  display: none !important;
}
```

Or remove it from the HTML in `app/views/scout/index.html.erb`:
```erb
<!-- Comment out or delete this: -->
<%# 
<button type="button" class="gif-btn" id="gif-button" title="Add GIF">
  <i data-lucide="image"></i>
</button>
%>
```

---

## Giphy API Limits

**Free Tier:**
- 42 requests per hour per IP
- 1000 requests per day
- Perfect for small teams!

**If you need more:**
- Production tier available at https://developers.giphy.com/dashboard/

---

## Troubleshooting

### "403 BANNED" Error
- The public beta key is blocked
- You MUST use your own API key
- Follow Step 1-3 above

### "Network Error"
- Check internet connection
- Verify API key is correct
- Check Rails logs for details

### GIFs Not Loading
- Hard refresh browser (Cmd+Shift+R / Ctrl+Shift+R)
- Check browser console for errors
- Verify credentials were saved correctly:
  ```bash
  rails credentials:show
  ```

---

## Current Status

✅ **Emoji reactions** - Work without any API keys!  
✅ **Emoji picker** - Work without any API keys!  
✅ **@Mentions** - Work without any API keys!  
⚙️ **GIF search** - Requires free Giphy API key  

**Bottom line**: Everything works except GIFs until you add your free API key! 🎉

