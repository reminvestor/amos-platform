# Gap Analysis Cleanup & Revision Report

**Date:** 2026-02-13
**Branch:** `security/row-level-security`

---

## Background

A gap analysis identified 12 implementation tasks across 3 sprints. Agent teams executed all 12 tasks, but the gap analysis itself was flawed - it missed significant existing functionality. The project lead confirmed: *"a lot of stuff is actually there and it just missed it."*

This document records the post-implementation audit, what was kept, what was removed as dead code, and the database cleanup performed.

---

## Audit Summary

### What Already Existed (Gap Analysis Missed)

| Feature | Pre-Existing Location | Notes |
|---------|----------------------|-------|
| ObservabilityEvent model | `app/models/observability_event.rb` | Was a 130-line stub with `EmptyRelation` pattern |
| ObservabilityEvent table | `db/migrate/20251026181925_create_observability_events.rb` | Table created Oct 2025 |
| ObservabilityService | `app/services/observability_service.rb` | Service existed but flushed buffer to nothing |

### Agent Changes Kept (Genuinely New / Useful)

| Change | Files | Reason Kept |
|--------|-------|-------------|
| ObservabilityEvent model upgrade | `app/models/observability_event.rb` | Replaced 130-line stub with real ActiveRecord model + `batch_insert` |
| PersistObservabilityEventsJob | `app/jobs/persist_observability_events_job.rb` | Wires ObservabilityService buffer to actual DB persistence |
| ObservabilityService flush fix | `app/services/observability_service.rb` | Buffer now persists instead of discarding |
| Production log level fix | `config/environments/production.rb` | Changed default from `debug` to `info` |
| UserEvent model | `app/models/user_event.rb` | Product analytics (funnel/cohort) - different purpose from Activity model (CRM) |
| EventTrackable concern | `app/controllers/concerns/event_trackable.rb` | Controller helper for async event tracking |
| TrackUserEventJob | `app/jobs/track_user_event_job.rb` | Async event persistence |
| Onboarding user columns | `db/migrate/20260213000004` | `onboarding_step`, `onboarding_started_at`, `onboarding_completed_at` on users table |
| Onboarding step tracking | `app/controllers/onboarding_wizard_controller.rb` | Tracks which step user is on, fires analytics events |
| Event tracking in controllers | registrations, scout, billing, onboarding controllers | Tracks signups, chat, billing, onboarding events |
| Admin Feedbacks dashboard | `app/controllers/admin/feedbacks_controller.rb` | Admin view of user feedback aggregation |
| Admin Feedbacks view | `app/views/admin/feedbacks/index.html.erb` | Dashboard with Chart.js charts and tables |
| Feedback comment UX | `feedback_controller.js`, `_feedback_buttons.html.erb` | Comment prompt on thumbs-down |
| Template entity scoping | `db/migrate/20260213175334`, `workflow_template.rb` | `entity_id`, `tags`, `industry`, `shared` columns |
| Template industry/tags | All 6 YAML templates | Added industry and tags metadata fields |
| Template loader update | `workflow_template_loader.rb` | Parses industry/tags from YAML |
| Template analytics | `admin/observability_controller.rb`, `_template_analytics.html.erb` | Template usage stats in admin dashboard |
| Template Gallery canvas | `_template_gallery.html.erb` | Dynamic template browser (different from static `_template_library`) |
| Template Gallery JS | `template_gallery_controller.js` | Stimulus controller for filtering/search |
| Quick action personalization | `scout_controller.rb` | `newly_onboarded?` + `build_personalized_actions` |
| Quick actions in view | `scout/index.html.erb` | `PERSONALIZED_ACTIONS` variable injection |
| Routes | `config/routes.rb` | admin/feedbacks, workflow_templates, template_gallery |

### Agent Changes Removed (Dead Code)

| Change | Files | Why Removed |
|--------|-------|-------------|
| OnboardingProgress model | `app/models/onboarding_progress.rb` | Duplicated User model's `onboarding_step`/`started_at`/`completed_at` columns |
| OnboardingProgress migration | `db/migrate/20260213000005_create_onboarding_progresses.rb` | Created redundant table |
| OnboardingProgress association | `app/models/user.rb` | `has_one :onboarding_progress` - for deleted model |
| OnboardingProgress controller methods | `app/controllers/onboarding_wizard_controller.rb` | `onboarding_progress`, `persist_step`, `persist_wizard_data`, `restore_session_from_progress!` + all call sites |
| Orphan migration entry | `schema_migrations` table | `20260213000001` - agents tried to recreate existing observability_events table |

---

## Cleanup Actions Performed

### 1. Files Deleted

- `app/models/onboarding_progress.rb`
- `db/migrate/20260213000005_create_onboarding_progresses.rb`

### 2. Files Edited

**`app/models/user.rb`**
- Removed: `has_one :onboarding_progress, dependent: :destroy`

**`app/controllers/onboarding_wizard_controller.rb`**
- Removed: `restore_session_from_progress!` call from `show`
- Removed: All `onboarding_progress.get_data(...)` fallbacks (reverted to session-only)
- Removed: `persist_step(@step)` call from `show`
- Removed: All `persist_wizard_data(key, value)` calls from `update`
- Removed: `onboarding_progress.complete!` calls from `skip` and `finalize_onboarding`
- Removed: Private methods `onboarding_progress`, `persist_step`, `persist_wizard_data`, `restore_session_from_progress!`
- Kept: `include EventTrackable`, `track_event(...)` calls, `update_columns(onboarding_step:, ...)` calls

**`app/models/observability_event.rb`**
- Fixed: `batch_insert` method referenced nonexistent `workflow_execution_id` and `task_session_id` columns
- Mapped to actual table columns: `resource_type`, `resource_id`, `status`, `error_message`

### 3. Database Cleanup

```sql
-- Dropped redundant table
DROP TABLE onboarding_progresses;

-- Removed orphan migration entries
DELETE FROM schema_migrations WHERE version = '20260213000001';
DELETE FROM schema_migrations WHERE version = '20260213000005';
```

Schema regenerated via `rails db:schema:dump`.

### 4. Test Verification

Full test suite run: **2729 runs, 8330 assertions, 0 new failures from cleanup.**

All 9 failures/errors are pre-existing in unrelated tests (`quarantined_llm_service_test`, `sprint4_website_canvas_ecosystem_test`, `document_processor_test`).

---

## Architectural Notes

### Why UserEvent != Activity (Not Redundant)

| | UserEvent | Activity |
|---|-----------|----------|
| **Purpose** | Product analytics (funnel, cohort, feature adoption) | CRM activity tracking (calls, emails, meetings) |
| **Scope** | Platform-wide user behavior | Contact-centric interactions |
| **Examples** | `onboarding.completed`, `chat.started`, `signup` | "Called John about deal", "Sent proposal email" |
| **Used by** | Admin dashboards, analytics | CRM pipeline, contact timeline |

### Why Onboarding Uses User Columns (Not Separate Table)

The User model already has `onboarding_step`, `onboarding_started_at`, and `onboarding_completed_at` columns (added by migration `20260213000004`). The OnboardingProgress model was a redundant parallel tracking mechanism. Session-based wizard data + user columns is sufficient since onboarding is a one-time flow.
