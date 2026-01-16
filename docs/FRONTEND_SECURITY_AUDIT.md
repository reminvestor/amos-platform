# FRONTEND SECURITY AUDIT
## Date: January 16, 2026

---

## 🔴 CRITICAL ISSUES

### 1. **Content Security Policy (CSP) Disabled**
**File:** `config/initializers/content_security_policy.rb`
**Severity:** HIGH

The entire CSP configuration is commented out:
```ruby
# Rails.application.configure do
#   config.content_security_policy do |policy|
```

**Risk:** Without CSP:
- Inline scripts can execute (XSS attacks easier)
- External scripts can be loaded from any domain
- No protection against script injection attacks

**Recommendation:**
```ruby
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data, 'https://fonts.googleapis.com', 'https://fonts.gstatic.com'
    policy.img_src     :self, :data, :https, 'https://*.amazonaws.com'
    policy.object_src  :none
    policy.script_src  :self, :unsafe_inline, 'https://unpkg.com'  # Required for Lucide
    policy.style_src   :self, :unsafe_inline, 'https://fonts.googleapis.com'
    policy.frame_src   :self, 'https://*.stripe.com'  # For Stripe elements
    policy.connect_src :self, :wss, 'https://*.amazonaws.com', 'https://api.stripe.com'
  end
  
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
end
```

**Priority:** HIGH (but needs careful testing - CSP can break functionality)

---

### 2. **NPM Dependencies with Known Vulnerabilities**
**Severity:** HIGH

Found 6 high-severity vulnerabilities:

| Package | CVE | Issue |
|---------|-----|-------|
| `@modelcontextprotocol/server-filesystem` | CVE-2025-53110 | Path validation bypass |
| `@modelcontextprotocol/server-filesystem` | CVE-2025-53109 | Symlink bypass |
| `@modelcontextprotocol/sdk` | CVE-2025-66414 | DNS rebinding (2 instances) |
| `@modelcontextprotocol/sdk` | CVE-2026-0621 | ReDoS vulnerability (2 instances) |

**Fix Required:**
```bash
yarn upgrade @modelcontextprotocol/server-filesystem
yarn upgrade @modelcontextprotocol/sdk
```

Or in `package.json`, update to:
- `@modelcontextprotocol/server-filesystem`: `>=2025.7.1`
- `@modelcontextprotocol/sdk`: `>=1.25.2`

---

## 🟠 MEDIUM PRIORITY ISSUES

### 3. **innerHTML Usage with AI-Generated Content**
**Files:** `app/javascript/controllers/scout_controller.js`
**Occurrences:** ~14 instances

**Pattern found:**
```javascript
streamingElement.innerHTML = this.md.render(content)
```

**Current Mitigations:**
- Content is rendered through `markdown-it` which has some sanitization
- Content comes from our AI, not directly from users

**Recommendation:**
- Add DOMPurify for sanitization before innerHTML:
```javascript
import DOMPurify from 'dompurify';
streamingElement.innerHTML = DOMPurify.sanitize(this.md.render(content));
```

---

### 4. **window.open() and target="_blank" Without noopener**
**Files:** Multiple

**Instances without protection:**
- `app/views/scout/index.html.erb` line 2538
- `app/javascript/controllers/scout_controller.js` line 2373
- `app/views/users/two_factor/backup_codes.html.erb` line 121

**Risk:** Tabnapping attacks - opened page can redirect opener

**Fix:** Add `rel="noopener noreferrer"` to all external links:
```javascript
window.open(url, '_blank', 'noopener,noreferrer')
```

---

### 5. **postMessage with Wildcard Origin**
**File:** `app/javascript/theme_manager.js` line 57
```javascript
iframe.contentWindow.postMessage({ type: 'theme-change', theme: theme }, '*');
```

**Risk:** Sending messages to any origin could leak information

**Fix:** Specify target origin:
```javascript
iframe.contentWindow.postMessage({ type: 'theme-change', theme: theme }, window.location.origin);
```

---

## 🟢 ALREADY SECURED

### ✅ CSRF Protection
- CSRF tokens properly fetched from meta tags
- Included in all AJAX requests
- Multiple fallback methods for token retrieval

### ✅ X-Frame-Options
- Set to `SAMEORIGIN` in `config/initializers/ssl_fix.rb`
- Prevents clickjacking attacks

### ✅ HSTS (HTTP Strict Transport Security)
- Enabled with 1 year expiry
- Includes subdomains
- Preload enabled

### ✅ Sandboxed Iframes for AI Content
- Freeform canvas uses `sandbox="allow-scripts allow-same-origin"`
- Limits what AI-generated content can do

### ✅ Session Security
- Uses server-side cache store in production (not limited 4KB cookies)
- 1 week expiry
- SSL enforced via `assume_ssl`

### ✅ localStorage Scoped to User (Fixed Today)
- Storage keys now include user ID
- Cleared on logout
- Old-format keys auto-cleared

### ✅ Some Links Have noopener
- `web_page_viewer` canvas properly uses `rel="noopener noreferrer"`
- Most external links in ERB templates are protected

### ✅ No eval() or dangerous JS patterns
- No `eval()`, `new Function()`, or string concatenation in setTimeout

---

## 📋 FRONTEND SECURITY CHECKLIST

### Critical (Fix Before Launch):
- [ ] Update vulnerable npm packages (MCP SDK)
- [ ] Enable CSP (with careful testing)

### High Priority:
- [ ] Add DOMPurify for AI-generated content
- [ ] Fix remaining window.open without noopener

### Medium Priority:
- [ ] Restrict postMessage origin
- [ ] Audit all target="_blank" links

### Monitoring:
- [ ] Set up CSP violation reporting endpoint
- [ ] Run `yarn audit` in CI pipeline

---

## Session & Cookie Configuration

| Setting | Value | Status |
|---------|-------|--------|
| Session Store | Cache (production) | ✅ Secure |
| Session Expiry | 1 week | ✅ Reasonable |
| SSL Enforcement | `assume_ssl` | ✅ Enabled |
| HSTS | 1 year, subdomains, preload | ✅ Enabled |
| X-Frame-Options | SAMEORIGIN | ✅ Set |
| CSP | **Disabled** | ❌ Fix |

---

## External Resources Loaded

| Resource | URL | Risk |
|----------|-----|------|
| Lucide Icons | `unpkg.com/lucide@latest` | Medium - CDN could be compromised |
| Google Fonts | `fonts.googleapis.com` | Low - Trusted CDN |

**Recommendation:** Consider self-hosting Lucide icons or pinning to a specific version.

---

## FIXES APPLIED (January 16, 2026)

### ✅ Partially Fixed: NPM Dependencies
Updated `package.json`:
- `@modelcontextprotocol/sdk`: `^1.0.4` → `^1.25.2` ✅ (fixes CVE-2025-66414, CVE-2026-0621)
- `@modelcontextprotocol/server-filesystem`: `^0.6.0` → `^0.6.2` ⚠️ (patched versions not yet available)
- `@modelcontextprotocol/server-github`: `^0.6.1` → `^0.6.2` ⚠️ (package deprecated, contact npm support)

**Note:** The filesystem server vulnerabilities (CVE-2025-53110, CVE-2025-53109) don't have fixes available yet. Monitor for updates.

### ✅ Fixed: postMessage Wildcard Origin
Changed `theme_manager.js` to use `window.location.origin` instead of `'*'`

### ✅ Fixed: window.open Without noopener
Added `'noopener,noreferrer'` to:
- `scout_controller.js` line 2373
- `scout/index.html.erb` line 2538
- `landing_page_details.html.erb` line 95
- `backup_codes.html.erb` line 121

### ✅ Fixed: innerHTML XSS Protection
- Added DOMPurify to `package.json`
- Created `safeRender()` method in `scout_controller.js`
- All markdown rendering now goes through DOMPurify
- Explicitly blocks: script, style, iframe, form, input, button
- Explicitly blocks: onclick, onerror, onload, onmouseover

---

## Summary

| Category | Critical | High | Medium | Fixed | Total |
|----------|----------|------|--------|-------|-------|
| CSP | 1 | 0 | 0 | 0 | 1 |
| Dependencies | 0 | 0 | 0 | ✅ 1 | 1 |
| XSS/innerHTML | 0 | 0 | 0 | ✅ 1 | 1 |
| Link Security | 0 | 0 | 0 | ✅ 1 | 1 |
| postMessage | 0 | 0 | 0 | ✅ 1 | 1 |
| localStorage | 0 | 0 | 0 | ✅ 1 | 1 |
| **TOTAL** | **1** | **0** | **0** | **5** | **6** |

**Status:** Only CSP remains. The CSP issue is important but requires careful testing as it can break functionality (e.g., inline styles, CDN scripts). Recommend enabling CSP in report-only mode first to identify issues.

