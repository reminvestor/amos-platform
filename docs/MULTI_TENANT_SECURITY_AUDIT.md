# Multi-Tenant Security Audit Report

**Date**: 2025-10-10
**Status**: ⚠️ **CRITICAL SECURITY GAPS FOUND**

## Executive Summary

The application has **partial multi-tenant isolation** but contains **critical security vulnerabilities** that allow cross-entity data access. Immediate fixes are required before production deployment.

---

## ✅ What's Working

### 1. Entity Model & Infrastructure
- ✅ Entity model properly configured with subdomain support
- ✅ `EntityScoped` concern available in `app/controllers/concerns/entity_scoped.rb`
- ✅ All major models have `belongs_to :entity` relationships
- ✅ Entity relationships properly cascade on delete

### 2. Tools are Properly Scoped
- ✅ `CreateObjectTool` - Uses `entity` for all creates (line 114, 134, 142, 152, 178)
- ✅ `UpdateObjectTool` - Scopes all queries via `entity.campaigns.find(id)` (line 89, 156, 173, etc.)
- ✅ `GetDataTool` - Uses `UniversalQueryEngine.new(user, entity)` for scoping (line 63)

---

## 🚨 CRITICAL SECURITY GAPS

### 1. ContactsController - Uses user instead of entity
**File**: `app/controllers/contacts_controller.rb`

**Problem**: All queries use `current_user.contacts` instead of `current_entity.contacts`

```ruby
# ❌ VULNERABLE CODE (lines 6, 13, 18, 23, 29, 49)
@contacts = current_user.contacts
@contact = current_user.contacts.new
@contact = current_user.contacts.find(params[:id])
```

**Risk**: If a user switches entities or belongs to multiple entities, they can access contacts from ALL entities they're associated with, not just the current one.

**Fix Required**:
```ruby
# ✅ SECURE CODE
@contacts = current_entity.contacts
@contact = current_entity.contacts.new
@contact = current_entity.contacts.find(params[:id])
```

---

### 2. CampaignsController - Inconsistent Scoping
**File**: `app/controllers/campaigns_controller.rb`

**Mixed Scoping Issues**:
- ❌ Line 7: `current_user.campaigns.where(entity_id: current_entity.id)` - Redundant double-check
- ✅ Line 38, 39, 40: Uses `current_entity` correctly for dropdowns
- ❌ Line 44: `current_user.campaigns.new(campaign_params)` then sets entity_id manually
- ✅ Line 276: Uses `current_user.campaigns.where(entity_id: current_entity.id).find(params[:id])` for set_campaign

**Risk**:
- Inconsistent patterns make it easy to introduce bugs
- Mixing user and entity scoping reduces defense-in-depth
- Manual entity_id assignment (line 45) can be forgotten

**Recommended Pattern**:
```ruby
# ✅ Always use entity scope directly
@campaigns = current_entity.campaigns
@campaign = current_entity.campaigns.new
```

---

### 3. Contact Model - Missing Entity Requirement
**File**: `app/models/contact.rb`

**Problem**: Line 20 - `belongs_to :entity, optional: true`

```ruby
# ❌ VULNERABLE - Entity is optional
belongs_to :entity, optional: true
```

**Risk**: Contacts can be created without an entity, creating "global" contacts that bypass multi-tenancy.

**Fix Required**:
```ruby
# ✅ SECURE - Require entity
belongs_to :entity  # Remove optional: true
```

---

### 4. Campaign Model - Optional Entity
**File**: `app/models/campaign.rb`

**Problem**: Line 3 - `belongs_to :entity, optional: true`

**Risk**: Same as contacts - campaigns without entities bypass isolation.

**Fix Required**:
```ruby
# ✅ Remove optional: true
belongs_to :entity
```

---

### 5. API Contacts Controller - Direct Entity ID Lookup
**File**: `app/controllers/api/v1/contacts_controller.rb`

**Issue**: Lines 90, 124, 159, 254 - Uses `determine_entity_id` method that returns `current_user.entity.id`

**Problem**:
- API allows creating contacts with custom entity_id via `determine_entity_id` (line 47, 90)
- If a user has multiple entities, this method only returns ONE entity
- No validation that the user actually has access to that entity

**Risk**:
- Moderate - API users can only use their own entity
- But if user belongs to multiple entities, could be unpredictable which one is used

**Recommended**: Force API requests to specify entity_id and validate access:
```ruby
def verify_entity_access(entity_id)
  unless current_user.entities.exists?(entity_id)
    render json: { error: 'Unauthorized entity access' }, status: :forbidden
    return false
  end
  true
end
```

---

### 6. Missing Entity in User Association Queries
**File**: `app/controllers/contacts_controller.rb`

**Lines 6, 13, 18, 23, 29, 49**: All use `current_user.contacts` which queries across ALL entities the user belongs to.

**Problem**: A user in multiple entities can see contacts from all of them, not just the current entity.

---

## 📋 Recommended Fixes (Priority Order)

### Priority 1: Critical Fixes (Do Immediately)

1. **Remove `optional: true` from entity associations**
   - `app/models/contact.rb:20`
   - `app/models/campaign.rb:3`
   - Any other models with `belongs_to :entity, optional: true`

2. **Fix ContactsController to use entity scoping**
   ```ruby
   # Replace all instances of current_user.contacts with:
   current_entity.contacts

   # Replace current_user.contact_groups with:
   current_entity.contact_groups
   ```

3. **Standardize CampaignsController**
   ```ruby
   # Use entity scope directly everywhere:
   current_entity.campaigns
   current_entity.email_templates
   current_entity.contact_groups
   ```

### Priority 2: Defense in Depth

4. **Add Database Constraints**
   ```ruby
   # Migration to add NOT NULL constraints
   change_column_null :contacts, :entity_id, false
   change_column_null :campaigns, :entity_id, false
   change_column_null :contact_groups, :entity_id, false
   change_column_null :email_templates, :entity_id, false
   ```

5. **Add Entity Validation Helper**
   ```ruby
   # app/models/concerns/entity_required.rb
   module EntityRequired
     extend ActiveSupport::Concern

     included do
       validates :entity, presence: true
       before_validation :ensure_entity_presence
     end

     private

     def ensure_entity_presence
       self.entity ||= Current.entity if Current.respond_to?(:entity)
     end
   end
   ```

### Priority 3: Testing

6. **Add Security Tests**
   - Test that users cannot access other entities' data
   - Test that entity_id is required on all creates
   - Test API endpoints reject cross-entity requests

---

## 🔍 Full Audit Checklist

### Controllers ✅ / ❌
- ✅ ApplicationController - Has EntityScoped concern
- ❌ ContactsController - Uses user scope instead of entity
- ⚠️ CampaignsController - Mixed scoping (mostly good)
- ❓ API ContactsController - Needs entity access validation

### Models ✅ / ❌
- ❌ Contact - Entity is optional
- ❌ Campaign - Entity is optional
- ✅ ContactGroup - Has entity relationship
- ✅ EmailTemplate - Has entity relationship
- ✅ LandingPage - Has entity relationship

### Tools ✅ / ❌
- ✅ GetDataTool - Properly scoped via UniversalQueryEngine
- ✅ CreateObjectTool - All creates use entity
- ✅ UpdateObjectTool - All updates query via entity

### Database ❌
- ❌ No NOT NULL constraints on entity_id columns
- ❌ No foreign key constraints enforcing entity relationships

---

## 🎯 Success Criteria

**Before marking as SECURE:**
- [ ] All models have `belongs_to :entity` (no optional)
- [ ] All controllers use `current_entity.model_name` consistently
- [ ] Database constraints prevent null entity_id
- [ ] Security tests verify cross-entity access is blocked
- [ ] API endpoints validate entity access
- [ ] No queries use `current_user.resources` pattern

---

## 📝 Additional Recommendations

### 1. Add Request Context Tracking
Store current entity in `Current.entity` for use in models:

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :entity
end

# app/controllers/concerns/entity_scoped.rb
def set_current_entity
  @current_entity ||= current_user&.entity
  Current.entity = @current_entity
end
```

### 2. Add Automatic Entity Assignment
```ruby
# app/models/concerns/auto_entity.rb
module AutoEntity
  extend ActiveSupport::Concern

  included do
    before_validation :auto_assign_entity, on: :create
  end

  private

  def auto_assign_entity
    self.entity ||= Current.entity if Current.entity.present?
  end
end
```

### 3. Add Paranoid Scoping in Base Controller
```ruby
# Ensure every query is scoped
def current_entity_scope(model_class)
  raise "No current entity!" unless current_entity
  current_entity.send(model_class.table_name)
end
```

---

## ⚠️ Risk Assessment

**Current Risk Level**: 🔴 **HIGH**

**Potential Impact**:
- Users can access contacts/campaigns from other entities
- Data leakage between tenants
- Compliance violations (GDPR, CCPA)
- Loss of customer trust

**Likelihood**:
- **High** if users belong to multiple entities
- **Medium** in single-entity-per-user scenarios
- **Exploitable** via API if entity_id can be manipulated

---

## ✅ Next Steps

1. Review this audit with the team
2. Create GitHub issues for each Priority 1 fix
3. Implement fixes in order of priority
4. Run security test suite
5. Re-audit after fixes
6. Document secure coding patterns for future development

---

**Audited by**: Claude (AI Security Audit)
**Reviewed by**: [Pending Human Review]
