# 🚨 MIGRATION REQUIRED FOR PRODUCTION

## Quick Summary

**Run this ONE command in production**:
```bash
rails db:migrate
```

That's it! This will fix the integration system error.

---

## What the Migration Does

**File**: `db/migrate/20251014235445_add_is_enabled_to_integration_operations.rb`

**Changes**:
- Adds `is_enabled` column to `integration_operations` table
- Default: `true`
- Backfills all existing operations
- Adds index

**Why Needed**:
- UniversalIntegrationExecutor (built today) queries `where(is_enabled: true)`
- Production database doesn't have this column yet
- Error: `column integration_operations.is_enabled does not exist`

**Safe**: Yes - zero downtime, backwards compatible

---

## How to Run

### Option 1: Direct (Recommended)
```bash
# SSH to production
cd /path/to/app
rails db:migrate
```

### Option 2: Via AWS Script
```bash
./aws/run-migration.sh
```

### Option 3: Via Deployment
Your normal deployment process should auto-run migrations.

---

## After Running

✅ Integration system will work  
✅ execute_integration tool will work  
✅ "List Stripe customers" will work  
✅ All integration features operational  

---

**Status**: Migration ready and waiting. Run `rails db:migrate` in production! ⏳

