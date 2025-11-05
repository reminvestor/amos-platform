# AMOS Security Guide

Comprehensive security documentation for the AMOS platform covering authentication, authorization, multi-tenant isolation, and security best practices.

## Table of Contents

- [Security Architecture](#security-architecture)
- [Authentication System](#authentication-system)
- [Authorization & Access Control](#authorization--access-control)
- [Multi-Tenant Isolation](#multi-tenant-isolation)
- [Admin Area Protection](#admin-area-protection)
- [API Security](#api-security)
- [Security Audit Tool](#security-audit-tool)
- [Common Security Patterns](#common-security-patterns)
- [Fixing Security Issues](#fixing-security-issues)

---

## Security Architecture

AMOS uses a **defense-in-depth** security model with multiple layers:

```
┌─────────────────────────────────────────────────┐
│  1. Network Layer (HTTPS, Rate Limiting)        │
├─────────────────────────────────────────────────┤
│  2. Authentication (Devise)                     │
├─────────────────────────────────────────────────┤
│  3. Session Management (Encrypted Cookies)      │
├─────────────────────────────────────────────────┤
│  4. Authorization (Role-Based Access Control)   │
├─────────────────────────────────────────────────┤
│  5. Entity Isolation (Multi-Tenant Scoping)     │
├─────────────────────────────────────────────────┤
│  6. CSRF Protection (Rails built-in)            │
├─────────────────────────────────────────────────┤
│  7. SQL Injection Prevention (ActiveRecord)     │
└─────────────────────────────────────────────────┘
```

**Key Principles:**
- **Secure by Default** - All routes require authentication unless explicitly public
- **Least Privilege** - Users have minimum necessary permissions
- **Fail Securely** - Errors deny access, never grant it
- **Audit Everything** - All security events are logged

---

## Authentication System

### Devise Configuration

AMOS uses **Devise** for user authentication with the following modules:

**Enabled Modules:**
- `:database_authenticatable` - Password-based login
- `:registerable` - User sign-up
- `:recoverable` - Password reset
- `:rememberable` - "Remember me" functionality
- `:trackable` - Login tracking
- `:validatable` - Email/password validation
- `:lockable` - Account lockout after failed attempts

**Security Settings:**
```ruby
# config/initializers/devise.rb
config.lock_strategy = :failed_attempts
config.unlock_strategy = :time
config.maximum_attempts = 5  # Lock after 5 failed logins
config.unlock_in = 1.hour
config.password_length = 8..128
```

### Password Security

**Requirements:**
- Minimum 8 characters (12+ recommended)
- Hashed with bcrypt (cost factor 12)
- Salted automatically by Devise
- Passwords never stored in plaintext
- Passwords never logged or displayed

**Implementation:**
```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable, :lockable

  # Bcrypt handles hashing automatically
end
```

### Session Management

**Configuration:**
- Sessions stored in encrypted cookies
- 24-hour session timeout for regular users
- 4-hour session timeout for admin users
- Automatic session invalidation on logout
- CSRF token validation on all state-changing requests

---

## Authorization & Access Control

AMOS implements **three-tier role-based access control**:

### 1. User Roles (Platform-Wide)

```ruby
# app/models/user.rb
enum role: {
  viewer: 0,    # Read-only access
  marketer: 1,  # Create/edit campaigns
  admin: 2      # Full entity management
}
```

**Permissions:**

| Role | View Data | Create Campaigns | Manage Users | Delete Data |
|------|-----------|------------------|--------------|-------------|
| Viewer | ✅ | ❌ | ❌ | ❌ |
| Marketer | ✅ | ✅ | ❌ | ❌ |
| Admin | ✅ | ✅ | ✅ | ✅ |

### 2. EntityUser Roles (Tenant-Level)

```ruby
# app/models/entity_user.rb
enum role: {
  member: 0,  # Basic access to entity
  admin: 1,   # Manage entity resources
  owner: 2    # Full entity control + billing
}
```

**Use Cases:**
- Users can have different roles in different entities
- Owner can manage billing and subscriptions
- Admin can invite users and manage settings
- Member has read/write access to campaigns

### 3. AdminUser Roles (Platform Administration)

```ruby
# app/models/admin_user.rb
enum role: {
  viewer: 0,       # Read-only admin access
  editor: 1,       # Modify configurations
  super_admin: 2   # Full system access
}
```

**Admin Hierarchy:**
- **Viewer**: Observability, metrics, read-only access
- **Editor**: Modify integrations, system settings
- **Super Admin**: User management, sensitive operations

---

## Multi-Tenant Isolation

**Critical Security Requirement:** Users from one entity MUST NOT access another entity's data.

### Entity Scoping Pattern

**Step 1: Model Association**
```ruby
# app/models/campaign.rb
class Campaign < ApplicationRecord
  belongs_to :entity  # REQUIRED for multi-tenant models

  validates :entity_id, presence: true
end
```

**Step 2: Database Migration**
```ruby
# db/migrate/xxx_add_entity_to_campaigns.rb
add_reference :campaigns, :entity, null: false, foreign_key: true
add_index :campaigns, :entity_id
```

**Step 3: Controller Scoping**
```ruby
# app/controllers/campaigns_controller.rb
class CampaignsController < ApplicationController
  include EntityScoped  # ✅ REQUIRED

  def index
    # EntityScoped automatically scopes to current_entity
    @campaigns = current_entity.campaigns
  end

  def show
    # Always scope through current_entity
    @campaign = current_entity.campaigns.find(params[:id])
  end
end
```

### EntityScoped Concern

```ruby
# app/controllers/concerns/entity_scoped.rb
module EntityScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_current_entity
    before_action :verify_entity_access
  end

  private

  def set_current_entity
    @current_entity = current_user.entity
  end

  def current_entity
    @current_entity
  end

  def verify_entity_access
    # Ensures user belongs to entity
    unless current_user.entity_id == @current_entity.id
      redirect_to root_path, alert: "Access denied"
    end
  end
end
```

### ⚠️ Common Pitfalls

**❌ WRONG - Allows cross-tenant access:**
```ruby
def show
  @campaign = Campaign.find(params[:id])  # NO ENTITY SCOPE!
end
```

**✅ CORRECT - Entity-scoped:**
```ruby
def show
  @campaign = current_entity.campaigns.find(params[:id])
end
```

---

## Admin Area Protection

Admin routes are protected by a **separate authentication system** to prevent privilege escalation.

### Admin::BaseController

All admin controllers MUST inherit from `Admin::BaseController`:

```ruby
# app/controllers/admin/base_controller.rb
class Admin::BaseController < ApplicationController
  layout 'admin'

  before_action :authenticate_admin!
  before_action :log_admin_activity

  private

  def authenticate_admin!
    # Step 1: User must be logged in
    authenticate_user!

    # Step 2: User must have admin role
    unless current_user.admin?
      redirect_to root_path, alert: "Admin access required"
      return
    end

    # Step 3: Find or create AdminUser record
    @admin_user = AdminUser.find_by(email: current_user.email)

    unless @admin_user
      redirect_to root_path, alert: "Admin privileges not granted"
      return
    end
  end

  def current_admin
    @admin_user
  end

  def authorize_admin_action(required_role)
    case required_role
    when :super_admin
      unless current_admin.super_admin?
        redirect_to admin_root_path, alert: "Super admin access required"
      end
    when :editor
      unless current_admin.editor? || current_admin.super_admin?
        redirect_to admin_root_path, alert: "Editor access required"
      end
    # viewer can access everything by default
    end
  end

  def log_admin_activity
    # Audit logging for compliance
    Rails.logger.info("[ADMIN] #{current_admin.email} accessed #{request.path}")
  end
end
```

### Admin Controller Example

```ruby
# app/controllers/admin/system_settings_controller.rb
class Admin::SystemSettingsController < Admin::BaseController
  before_action -> { authorize_admin_action(:super_admin) }, only: [:destroy]

  def index
    # Any admin (viewer+) can view
    @settings = SystemSetting.all
  end

  def update
    # Editor or super_admin can modify
    authorize_admin_action(:editor)
    # ... update logic
  end

  def destroy
    # Only super_admin can delete
    # Already protected by before_action above
    # ... delete logic
  end
end
```

### ⚠️ Critical Security Issue: Auto-Escalation

**VULNERABILITY:**
```ruby
# app/controllers/admin/base_controller.rb
def authenticate_admin!
  @admin_user = AdminUser.find_or_create_by(email: current_user.email) do |admin|
    admin.role = :super_admin  # ❌ AUTO-ESCALATION!
  end
end
```

**Impact:** Any user with `user.role = :admin` automatically becomes `super_admin` when accessing `/admin`.

**FIX:**
```ruby
def authenticate_admin!
  @admin_user = AdminUser.find_by(email: current_user.email)

  unless @admin_user
    redirect_to root_path, alert: "Admin privileges not granted"
    return
  end
end
```

Create AdminUser records explicitly:
```bash
rails admin:create_user
rails admin:grant_access
```

---

## API Security

### API Key Storage

**❌ WRONG - Plaintext storage:**
```ruby
# app/models/user.rb
def generate_api_key
  self.api_key = SecureRandom.hex(32)
  save
end

def valid_api_key?(provided_key)
  api_key == provided_key  # ❌ Timing attack vulnerability
end
```

**Problems:**
1. Database breach exposes all API keys
2. Timing attack can leak key information
3. No key rotation mechanism

**✅ CORRECT - Hashed storage:**
```ruby
# app/models/user.rb
require 'bcrypt'

def generate_api_key
  raw_key = SecureRandom.hex(32)
  self.api_key_digest = BCrypt::Password.create(raw_key)
  save

  # Return raw key ONCE for user to save
  raw_key
end

def valid_api_key?(provided_key)
  return false unless api_key_digest

  BCrypt::Password.new(api_key_digest) == provided_key
rescue BCrypt::Errors::InvalidHash
  false
end
```

**Migration:**
```ruby
# db/migrate/xxx_add_api_key_digest_to_users.rb
class AddApiKeyDigestToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :api_key_digest, :string
    add_index :users, :api_key_digest

    # Remove plaintext column
    remove_column :users, :api_key
  end
end
```

### OAuth Token Encryption

**Encrypt sensitive credentials at rest:**

```ruby
# app/models/connection.rb
class Connection < ApplicationRecord
  # Rails 7+ built-in encryption
  encrypts :access_token
  encrypts :refresh_token

  # Automatically encrypts/decrypts on read/write
end
```

**Setup:**
```ruby
# config/credentials.yml.enc
active_record_encryption:
  primary_key: <%= SecureRandom.hex(32) %>
  deterministic_key: <%= SecureRandom.hex(32) %>
  key_derivation_salt: <%= SecureRandom.hex(32) %>
```

### Rate Limiting

**Rack::Attack configuration:**

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle('api/ip', limit: 100, period: 1.minute) do |req|
  req.ip if req.path.start_with?('/api')
end

Rack::Attack.throttle('logins/email', limit: 5, period: 20.minutes) do |req|
  if req.path == '/users/sign_in' && req.post?
    req.params['user']['email'].to_s.downcase.gsub(/\s+/, '')
  end
end
```

---

## Security Audit Tool

AMOS includes a comprehensive security audit tool to detect vulnerabilities.

### Running Audits

```bash
# Full audit
rails security:audit

# Specific categories
rails security:entity_isolation
rails security:admin_protection
rails security:role_checks
rails security:api_security
rails security:auth_bypass

# Generate report
rails security:report[security_report.txt]

# Interactive fix helper
rails security:fix
```

### What It Checks

**Entity Isolation:**
- ✅ Controllers have `EntityScoped` concern
- ✅ Models have `belongs_to :entity`
- ✅ No cross-tenant queries
- ✅ Proper use of `current_entity`

**Admin Protection:**
- ✅ All admin controllers inherit from `Admin::BaseController`
- ✅ `authenticate_admin!` is enforced
- ✅ No auto-escalation vulnerabilities
- ✅ Role-based authorization checks

**Role-Based Access:**
- ✅ User model has role enumeration
- ✅ EntityUser roles are enforced
- ✅ Destructive actions require authorization
- ✅ No privilege escalation paths

**API Security:**
- ✅ API keys are hashed (not plaintext)
- ✅ OAuth tokens are encrypted
- ✅ Secure token comparison (no timing attacks)
- ✅ Token rotation implemented

**Authentication:**
- ✅ All controllers require authentication
- ✅ Public actions explicitly skip authentication
- ✅ Devise properly configured
- ✅ Account lockout enabled

### Interpreting Results

**Severity Levels:**
- **CRITICAL** - Fix immediately (data breach risk)
- **HIGH** - Fix within 24 hours (significant vulnerability)
- **MEDIUM** - Fix within 1 week (security improvement)
- **LOW** - Fix as time permits (best practice)

---

## Common Security Patterns

### 1. Adding a New Multi-Tenant Model

```ruby
# 1. Generate model with entity reference
rails g model Post title:string content:text entity:references

# 2. Add validation
class Post < ApplicationRecord
  belongs_to :entity
  validates :entity_id, presence: true
end

# 3. Create controller with EntityScoped
class PostsController < ApplicationController
  include EntityScoped

  def index
    @posts = current_entity.posts
  end

  def create
    @post = current_entity.posts.build(post_params)
    # ...
  end
end
```

### 2. Adding a New Admin Controller

```ruby
# 1. Inherit from Admin::BaseController
class Admin::ReportsController < Admin::BaseController
  # Automatically protected

  def index
    # Any admin can view
    @reports = Report.all
  end

  def destroy
    # Only super_admin can delete
    authorize_admin_action(:super_admin)
    @report = Report.find(params[:id])
    @report.destroy
  end
end
```

### 3. Adding a Public Route

```ruby
# 1. Skip authentication
class LandingPagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show]

  def show
    @page = LandingPage.find_by!(slug: params[:slug])
    # Public access allowed
  end
end
```

### 4. Checking Permissions in Views

```erb
<!-- app/views/campaigns/show.html.erb -->
<% if current_user.admin? || current_user.marketer? %>
  <%= link_to "Edit", edit_campaign_path(@campaign) %>
<% end %>

<% if current_user.admin? %>
  <%= link_to "Delete", campaign_path(@campaign), method: :delete %>
<% end %>
```

---

## Fixing Security Issues

### Issue: Missing Entity Scoping

**Problem:**
```ruby
class CampaignsController < ApplicationController
  def index
    @campaigns = Campaign.all  # ❌ Cross-tenant access!
  end
end
```

**Fix:**
```ruby
class CampaignsController < ApplicationController
  include EntityScoped  # Add this

  def index
    @campaigns = current_entity.campaigns  # ✅ Entity-scoped
  end
end
```

### Issue: Plaintext API Keys

**Problem:**
```ruby
class User < ApplicationRecord
  def generate_api_key
    self.api_key = SecureRandom.hex(32)
  end
end
```

**Fix:**
```ruby
require 'bcrypt'

class User < ApplicationRecord
  # 1. Migration: Rename api_key to api_key_digest
  # 2. Update generation logic
  def generate_api_key
    raw_key = SecureRandom.hex(32)
    self.api_key_digest = BCrypt::Password.create(raw_key)
    save
    raw_key  # Return once for user to save
  end

  def valid_api_key?(provided_key)
    BCrypt::Password.new(api_key_digest) == provided_key
  end
end
```

### Issue: Admin Auto-Escalation

**Problem:**
```ruby
def authenticate_admin!
  @admin_user = AdminUser.find_or_create_by(email: current_user.email) do |admin|
    admin.role = :super_admin  # ❌ Auto-grants super_admin!
  end
end
```

**Fix:**
```ruby
def authenticate_admin!
  @admin_user = AdminUser.find_by(email: current_user.email)

  unless @admin_user
    redirect_to root_path, alert: "Admin access not granted"
    return
  end
end
```

Create admin users explicitly:
```bash
rails admin:create_user
# or
rails admin:grant_access
```

### Issue: Missing Authorization Checks

**Problem:**
```ruby
def destroy
  @campaign = current_entity.campaigns.find(params[:id])
  @campaign.destroy  # ❌ Any user can delete!
end
```

**Fix:**
```ruby
def destroy
  authorize_action!(:delete)  # ✅ Check permission first

  @campaign = current_entity.campaigns.find(params[:id])
  @campaign.destroy
end

private

def authorize_action!(action)
  unless current_user.admin?
    redirect_to root_path, alert: "Permission denied"
  end
end
```

---

## Security Checklist

Use this checklist when adding new features:

### For New Models
- [ ] Add `belongs_to :entity` if multi-tenant
- [ ] Add `validates :entity_id, presence: true`
- [ ] Add database foreign key constraint
- [ ] Test cross-tenant isolation

### For New Controllers
- [ ] Include `EntityScoped` if multi-tenant
- [ ] Add `before_action :authenticate_user!`
- [ ] Add authorization checks for destructive actions
- [ ] Test unauthorized access is blocked

### For New Admin Controllers
- [ ] Inherit from `Admin::BaseController`
- [ ] Add role-based authorization where needed
- [ ] Test non-admin users cannot access
- [ ] Add audit logging for sensitive actions

### For New API Endpoints
- [ ] Use token authentication (not cookies)
- [ ] Rate limit by IP and/or user
- [ ] Validate all input parameters
- [ ] Return minimal error information

### For New Features
- [ ] Run security audit: `rails security:audit`
- [ ] Review authentication requirements
- [ ] Review authorization rules
- [ ] Add security tests
- [ ] Document security assumptions

---

## Additional Resources

- [Rails Security Guide](https://guides.rubyonrails.org/security.html)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Devise Documentation](https://github.com/heartcombo/devise)
- [Rack::Attack Documentation](https://github.com/rack/rack-attack)

---

## Contact

For security issues, contact: security@amos.com

**DO NOT** create public GitHub issues for security vulnerabilities.
