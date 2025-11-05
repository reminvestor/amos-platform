# Security Audit

Comprehensive security audit to ensure user isolation, role-based access control, and admin area protection across the AMOS platform.

## Description

This command performs a deep security analysis of the application to detect vulnerabilities related to:
- **Entity Isolation** - Ensures multi-tenant data segregation
- **Admin Area Protection** - Verifies admin routes are properly secured
- **Role-Based Access Control** - Confirms role enforcement is working
- **API Security** - Checks for credential security issues
- **Authentication Bypass** - Detects potential authorization gaps

**What it does:**
- ✅ Scans all controllers for entity scoping violations
- ✅ Verifies admin controllers have proper authentication
- ✅ Checks role-based authorization implementation
- ✅ Audits model-level security (default_scope usage)
- ✅ Reviews API key storage security
- ✅ Detects privilege escalation vulnerabilities
- ✅ Generates detailed security report with severity ratings
- ✅ Provides fix recommendations for each issue

## Critical Security Issues We Check

### 1. Entity Isolation Violations (CRITICAL)
**Risk:** Users from one tenant accessing another tenant's data

**Checks:**
- Controllers without `EntityScoped` concern
- Models without entity_id foreign key
- Raw SQL queries bypassing ActiveRecord scopes
- Direct `Model.find()` calls without entity filtering

### 2. Admin Area Protection (CRITICAL)
**Risk:** Non-admin users accessing admin functionality

**Checks:**
- Admin controllers without `authenticate_admin!`
- Missing role verification in admin routes
- Auto-escalation vulnerabilities (regular user → super_admin)
- Admin namespace route protection

### 3. Role-Based Access Control (HIGH)
**Risk:** Users performing actions outside their permission level

**Checks:**
- Controllers missing authorization checks
- Role enumeration implementation
- Permission inheritance logic
- EntityUser role enforcement

### 4. API Key Security (CRITICAL)
**Risk:** Database breach exposing all API tokens

**Checks:**
- Plaintext API key storage
- Missing bcrypt hashing for tokens
- API key regeneration logic
- Secure comparison implementation

### 5. Authentication Bypass (CRITICAL)
**Risk:** Unauthenticated access to protected resources

**Checks:**
- Controllers missing `before_action :authenticate_user!`
- Public actions without explicit skip_authentication
- Devise configuration issues
- Session management vulnerabilities

## Usage

```bash
# Run full security audit
rails security:audit

# Run specific audit category
rails security:entity_isolation
rails security:admin_protection
rails security:role_checks
rails security:api_security
rails security:auth_bypass

# Run with verbose output
VERBOSE=true rails security:audit

# Generate security report file
rails security:report[security_report.txt]

# Run verbose audit with all details
rails security:verbose

# Interactive fix helper
rails security:fix

# Show security statistics
rails security:stats
```

### Docker Environment

```bash
# Inside Docker container
docker compose exec web rails security:audit

# Generate report file
docker compose exec web rails security:report[security_report.txt]

# Run specific category
docker compose exec web rails security:entity_isolation
```

## Security Report Format

The audit generates a structured report with:

```
=== AMOS SECURITY AUDIT REPORT ===
Run Date: 2025-11-05 14:30:00 UTC

CRITICAL ISSUES (3):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[CRITICAL] Plaintext API Keys
Location: app/models/user.rb:45
Risk: Database breach exposes all API tokens
Fix: Hash API keys using bcrypt before storage
Impact: All user accounts compromised if database leaked

[CRITICAL] Admin Auto-Escalation
Location: app/controllers/admin/base_controller.rb:12
Risk: Any user with role=admin auto-becomes super_admin
Fix: Remove auto-creation logic, use explicit role assignment
Impact: Regular admins gain unrestricted system access

[CRITICAL] Missing Entity Scope
Location: app/controllers/reports_controller.rb:15
Risk: Cross-tenant data access
Fix: Add EntityScoped concern or manual entity filtering
Impact: Users can view other tenants' reports

HIGH ISSUES (5):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
...

MEDIUM ISSUES (2):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
...

SUMMARY:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Issues: 10
Critical: 3
High: 5
Medium: 2
Low: 0

Controllers Scanned: 45
Models Scanned: 39
Routes Analyzed: 156
```

## Audit Categories Explained

### Entity Isolation Audit
Scans all controllers and models to ensure:
- Every entity-scoped model has `belongs_to :entity`
- Controllers include `EntityScoped` concern or manual filtering
- No `User.all`, `Campaign.all` without entity filter
- Proper use of `current_entity` in controllers

### Admin Protection Audit
Verifies admin namespace security:
- All `Admin::*Controller` inherit from `Admin::BaseController`
- `authenticate_admin!` is called before any admin action
- AdminUser roles are properly checked (viewer/editor/super_admin)
- No regular users can access `/admin/*` routes

### Role-Based Access Control Audit
Checks authorization enforcement:
- User model has role enumeration (admin/marketer/viewer)
- EntityUser roles are enforced (owner/admin/member)
- Controllers verify roles before destructive actions
- No role escalation vulnerabilities

### API Security Audit
Reviews credential management:
- API keys are hashed, not stored in plaintext
- OAuth tokens are encrypted at rest
- Secure token comparison (no timing attacks)
- Token rotation/expiration implemented

### Authentication Bypass Audit
Ensures authentication is required:
- All controllers have `before_action :authenticate_user!`
- Public actions explicitly skip authentication
- Devise properly configured
- No session fixation vulnerabilities

## When to Run This Command

### Before Every Deployment
```bash
/security-audit --report
```
- Catch security regressions before production
- Document security posture for compliance

### After Adding New Features
```bash
/security-audit entity-isolation
```
- Ensure new controllers are entity-scoped
- Verify new models have proper associations

### During Security Review
```bash
/security-audit --verbose
```
- Comprehensive analysis for security audits
- Generate evidence for SOC2/ISO27001 compliance

### When Debugging Access Issues
```bash
/security-audit admin-protection
/security-audit role-checks
```
- Diagnose authorization problems
- Verify role enforcement is working

## Fix Priority Guide

**Fix CRITICAL issues immediately:**
- Plaintext API keys → Switch to bcrypt hashing
- Admin auto-escalation → Remove auto-creation logic
- Missing entity scopes → Add EntityScoped concern

**Fix HIGH issues within 24 hours:**
- Missing authentication checks
- Role verification gaps
- SQL injection vulnerabilities

**Fix MEDIUM issues within 1 week:**
- Missing CSRF protection
- Insecure session configuration
- Missing rate limiting

**Fix LOW issues as time permits:**
- Coding standard violations
- Performance optimizations
- Documentation improvements

## Integration with CI/CD

Add security audits to your pipeline:

```yaml
# .github/workflows/security.yml
- name: Security Audit
  run: /security-audit
```

This catches security issues before code review.

## Related Commands

- `/run-tests security` - Run security-focused tests
- `/check-deployment` - Verify deployment security
- `/prepare-dev-env` - Includes security checks in setup

## Implementation Details

The audit uses static analysis to scan:
- Ruby files in `app/controllers/`
- Ruby files in `app/models/`
- Route definitions in `config/routes.rb`
- Devise configuration in `config/initializers/`

**Detection Methods:**
- AST parsing for Ruby code analysis
- Regex pattern matching for security anti-patterns
- Route introspection for access control
- Database schema analysis for foreign keys

## Limitations

This is a **static analysis tool** and cannot detect:
- Runtime logic errors
- Business logic authorization bugs
- Complex multi-step exploits
- Social engineering vulnerabilities

Always combine with:
- Manual penetration testing
- Code review
- Security-focused integration tests
- Third-party security scans

## Troubleshooting

**Audit fails to run?**
```bash
# Check Ruby syntax
rails runner 'puts "OK"'

# Verify Rails can boot
rails console
```

**Too many false positives?**
- Review the `SecurityAuditor::IGNORE_PATTERNS` configuration
- Add your controllers to allowlist if needed
- Check for custom authorization patterns

**Missing issues?**
- Update the auditor patterns in `lib/security_auditor.rb`
- Add custom checks for your auth system
- Combine with manual testing

## Security Best Practices

### For Controllers
```ruby
class MyController < ApplicationController
  include EntityScoped  # ✅ Always include for multi-tenant
  before_action :authenticate_user!  # ✅ Require authentication
  before_action :authorize_action  # ✅ Check permissions

  def index
    @records = current_entity.my_models  # ✅ Entity-scoped query
  end
end
```

### For Models
```ruby
class MyModel < ApplicationRecord
  belongs_to :entity  # ✅ Required for multi-tenant

  validates :entity_id, presence: true  # ✅ Prevent orphaned records

  # ✅ Avoid default_scope (makes testing hard)
  # Instead, scope in controller with current_entity
end
```

### For Admin Controllers
```ruby
class Admin::MyController < Admin::BaseController
  # ✅ Inherits authenticate_admin! from BaseController

  def index
    authorize_admin_action(:view)  # ✅ Check specific permission
  end
end
```

## Security Principles

1. **Defense in Depth** - Multiple layers of security
2. **Least Privilege** - Users have minimum required access
3. **Secure by Default** - Security is opt-out, not opt-in
4. **Fail Securely** - Errors deny access, not grant it
5. **Audit Everything** - Log all security-relevant events

---

**Remember:** Security is not a one-time task. Run this audit regularly and after every significant change.
