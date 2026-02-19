# AMOS Platform Gap Analysis & Hardening Plan

**Date:** February 13, 2026
**Prepared by:** Engineering
**Status:** Approved - Ready for implementation
**Trigger:** Email blast campaign targeting new signups in ~2 weeks

---

## Executive Summary

We audited five areas of the AMOS platform to assess readiness for a growth push. The platform has a strong foundation — 14+ analytics models, a comprehensive feedback system, a 9-step onboarding wizard, a 135-view admin dashboard, and a mature 3-phase workflow engine. However, critical instrumentation and UX gaps would leave us blind to conversion performance and vulnerable to new-user drop-off.

This report documents what exists, what's missing, and a 4-week implementation plan organized into three sprints.

### Key Findings at a Glance

| Area | Health | Biggest Risk |
|------|--------|-------------|
| Event Tracking | Strong infrastructure, no product analytics | Can't measure email blast ROI or signup-to-value funnel |
| User Feedback | Comprehensive thumbs up/down system | No admin visibility into aggregated sentiment |
| Onboarding | Well-built 9-step wizard | Session-based state — browser close loses all progress |
| Observability | Extensive admin dashboard + custom errors | No alerting — errors log but don't page anyone |
| Workflow Templates | Mature engine with 6 templates | No duplication, no vertical customization, no gallery |

### Decisions Made

| Decision | Outcome |
|----------|---------|
| Sentry/Error Tracking | **Deferred** — keep custom ErrorLogEntry system for now |
| Template Gallery Scope | **System + shared** — entities can publish templates for others |
| OpenTelemetry | **Deferred** — gems present, wiring postponed |
| Onboarding A/B Testing | **Deferred** — post-blast |

---

## 1. Event Tracking & Analytics

### What We Have

The platform has extensive *internal* event tracking with no external analytics dependencies:

| Model | Purpose | Key Metrics |
|-------|---------|-------------|
| `Activity` | CRM events (30+ types) | Contacts, emails, calls, meetings, AI actions |
| `IntegrationLog` | API audit trail | Request/response, duration, status, retry count |
| `AiUsageLog` | LLM usage | Model, tokens (in/out), cost in cents, duration |
| `ToolUsageMetric` | Tool invocations | Tool name, success/fail, latency |
| `EntityUsageMetric` | Service billing | Category, service, cost USD |
| `TaskEvent` | Workflow steps (20+ types) | Session sequencing, step timing |
| `AgentLightningTrace` | RL training data | Traces, rewards, token counts |
| `ModelQualityLog` | LLM performance | Success rates per model/tool combo |
| `DocumentAnalytics` | RAG document usage | Views, queries, retrieval counts |

**Services:** `Analytics::RealtimeService` (5s cache, SSE streaming), `ActivityService`, `TopPerformersService`, `HeatmapService`, `QueryExecutor`

**Frontend:** Real-time Chart.js dashboard via SSE at `/analytics/stream`

### What's Missing

- **Product analytics**: Zero tracking of user navigation, feature adoption, session duration, or funnel conversion
- **Cohort analysis**: Can't answer "what % of Week 1 signups created a campaign?"
- **`ObservabilityEvent` table**: Model exists as a stub — returns empty results, migration was never created
- **OpenTelemetry**: `opentelemetry-api` and `opentelemetry-instrumentation-base` gems installed but never initialized
- **Business metrics pipeline**: No way to measure email blast ROI end-to-end

---

## 2. User Feedback

### What We Have

A comprehensive feedback system tightly integrated with the learning pipeline:

- **`UserFeedback` model**: Thumbs up/down/neutral, polymorphic across 5 types (ScoutMessage, AgentPluginExecution, ScheduledTaskRun, WorkflowExecution, ToolExecution)
- **Two controllers**: `Scout::FeedbacksController` (web, session auth) and `Api::V1::FeedbacksController` (mobile, API key auth)
- **Stats API**: `/api/v1/feedbacks/stats` with satisfaction scores, daily trends, type breakdown
- **Implicit feedback**: `Learning::ImplicitFeedbackDetector` extracts signals from conversation patterns (positive/negative keywords, retry detection, topic changes)
- **Learning integration**: Feedback automatically updates `DecisionTrace` outcomes and `TaskExperience` utility scores
- **Agent reputation**: `combined_reputation_score` weights 40% technical + 40% user satisfaction + 20% ELO
- **Frontend**: Stimulus `feedback_controller.js` + reusable `_feedback_buttons.html.erb` partial
- **Duplicate prevention**: Unique constraint per item per session

### What's Missing

- **Problem reporting**: Users can thumbs-down but can't describe *what* went wrong (comment field exists in DB but UI doesn't expose it on negative feedback)
- **Admin aggregation**: No admin view showing sentiment trends — data only accessible via API
- **NPS/satisfaction survey**: No periodic check-ins
- **Onboarding feedback**: Wizard has no feedback capture point

---

## 3. Onboarding Flow

### What We Have

A well-built 9-step wizard with AI-powered website analysis:

```
Sign Up -> Payment Setup -> Legal -> Welcome -> About You -> Website Analysis
-> Your Business -> Use Cases -> Features -> Complete -> Chat
```

**Key capabilities:**
- `OnboardingWizardController` with step-by-step progression
- `OnboardingWebsiteAnalyzerService` auto-fills business profile from URL (name, industry, description, tagline, target audience, tone of voice, brand personality)
- Stripe payment setup with "Continue with Free Tokens" skip option
- Feature selection configures menu items and user spaces
- Free tokens credited on signup, affiliate referral tracking
- Google OAuth support
- Legacy conversational onboarding still routable (deprecated)

### What's Missing

- **Drop-off tracking**: `user.onboarded` is a boolean — no visibility into *which step* users abandon
- **Progress persistence**: All wizard state lives in Rails session — browser close means starting over
- **Re-engagement**: Users who quit mid-wizard are permanently lost (no email, no reminder)
- **Post-onboarding guidance**: After completion, user lands at `/chat` with generic quick-action cards (not personalized to their selections)
- **Error recovery**: Entity creation failure returns `nil` and logs an error but doesn't surface to user
- **A/B testing**: No variant support

---

## 4. Observability & Error Handling

### What We Have

| Component | Status | Details |
|-----------|--------|---------|
| Custom error classes | Complete | `AmosErrors` hierarchy — 10 specific types (Bedrock, Integration, Workflow, Tool, Campaign, etc.) |
| Error log model | Complete | `ErrorLogEntry` with SHA256 dedup, auto-ticket creation at 3+ occurrences |
| Admin dashboard | Extensive | 135+ views: user stats, integration health, API calls, AI costs, workflow metrics |
| Admin observability | Complete | Workflow status breakdown, performance metrics, error aggregation, trend charts |
| Health checks | Complete | 9+ endpoints (`/up`, `/health`, `/api/v1/health`, voice health, RAG health) |
| Admin auth | Complete | `AdminUser` with 3-tier roles (viewer/editor/super_admin), audit trail, lockout |
| Rate limiting | Complete | `Rack::Attack` — chat 50/min IP, API 100/min, login 5/20s, landing pages 10/hr |
| Background jobs | Partial | SolidQueue with 7 recurring tasks, no Mission Control UI |

### What's Missing

- **No commercial error tracking**: No Sentry, Rollbar, Honeybadger, etc. — errors stay in-database
- **No alerting**: `ErrorLogEntry` creates support tickets but doesn't page or email anyone
- **Production log level is DEBUG**: `config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "debug")` — extremely noisy
- **`ObservabilityEvent` table missing**: Stub model exists, migration never created
- **OpenTelemetry not wired**: Gems present, no exporters configured
- **No uptime monitoring**: Health endpoints exist but nothing polls them
- **No SolidQueue dashboard**: Jobs managed only through code/console

---

## 5. Workflow System & Templates

### What We Have

A mature 3-phase workflow engine:

| Component | Details |
|-----------|---------|
| Templates | 6 active V2 YAML templates (email campaign, landing page, analytics, email sequence, integration builder, add group to campaign) |
| Engine | GatherContextExecutor -> GoalExecutor -> ValidationExecutor |
| Execution modes | Adaptive (AI-planned), Prescribed (fixed sequence), Structured (data mapping) |
| Tracking | `WorkflowExecution`, `WorkflowStepExecution`, `WorkflowContext`, `WorkflowVariable` |
| Triggers | `WorkflowTrigger` — 10 types (form, webhook, schedule, record events, manual, integration) |
| Discovery | Auto-discovered from `app/workflow_templates/*.yml` — no registration needed |
| Snapshots | Full template spec preserved in `workflow_spec` JSONB at execution time |
| DB support | `WorkflowTemplate` model supports `is_system: false` for user-created templates |

### What's Missing

- **No duplication**: Can't clone a template to customize it
- **No entity scoping**: All templates are system-wide (no `entity_id` on `workflow_templates`)
- **No marketplace/gallery**: Users discover templates only through chat intent matching
- **No industry tagging**: Single `category` field, no vertical classification
- **No user-created template UI**: Schema supports it, no creation flow exposed
- **No template versioning**: Changes to YAML apply to all future runs
- **No usage analytics**: Can't see which templates are popular or have high success rates

---

## Implementation Plan

### Sprint 1 — Week 1: Metrics & Feedback

*Unblocks email blast ROI measurement*

| Task | Description | Complexity | Dependencies |
|------|-------------|-----------|--------------|
| **S1.1** Product Analytics | `UserEvent` model + `EventTrackable` concern + async job. Instrument signup, onboarding steps, first chat, payment. | Moderate | None |
| **S1.2** Onboarding Funnel | Add `onboarding_step`, `onboarding_started_at`, `onboarding_completed_at` to users. Track step-by-step drop-off. | Simple | S1.1 |
| **S1.3** Feedback Admin Dashboard | New admin controller/view aggregating `UserFeedback` — satisfaction score, daily trends, negative comments. | Simple | None |
| **S1.4** Problem Reporting | Show comment textarea on thumbs-down in chat. Backend already supports it (`UserFeedback.comment`). | Simple | None |

**New files:** `user_event.rb`, `event_trackable.rb`, `track_user_event_job.rb`, `admin/feedbacks_controller.rb`, `admin/feedbacks/index.html.erb`
**Modified files:** `registrations_controller.rb`, `onboarding_wizard_controller.rb`, `scout_controller.rb`, `feedback_controller.js`, `_feedback_buttons.html.erb`, `routes.rb`

### Sprint 2 — Weeks 2-3: Onboarding UX & Observability

*Improves experience for users arriving from the blast*

| Task | Description | Complexity | Dependencies |
|------|-------------|-----------|--------------|
| **S2.1** Onboarding Persistence | `OnboardingProgress` model persisting wizard state to DB. Resume from where you left off. | Moderate | S1.2 |
| **S2.2** First Action Guidance | Personalize post-onboarding quick-action cards based on selected features. | Simple | S2.1 |
| **S2.3** ObservabilityEvent Table | Create the migration, replace stub model, wire `ObservabilityService` buffer flush to DB. | Simple | None |
| **S2.4** Production Log Level | Change default from `debug` to `info`. One-line fix. | Trivial | None |

**New files:** `onboarding_progress.rb`, `CreateOnboardingProgresses` migration, `CreateObservabilityEvents` migration
**Modified files:** `onboarding_wizard_controller.rb`, `scout/index.html.erb`, `observability_event.rb`, `observability_service.rb`, `production.rb`

### Sprint 3 — Weeks 3-4: Vertical Template System

*Builds on stabilized workflow engine*

| Task | Description | Complexity | Dependencies |
|------|-------------|-----------|--------------|
| **S3.1** Template Duplication | Add `entity_id` to `workflow_templates`. `duplicate_for_entity()` method. CRUD controller. | Moderate | None |
| **S3.2** Industry Tagging | Add `tags` (jsonb) and `industry` (string) to templates. Update loader + YAML files. | Simple | S3.1 |
| **S3.3** Template Analytics | Admin view: template popularity, success rates, avg duration. Query `WorkflowExecution` aggregates. | Simple | None |
| **S3.4** Template Gallery | New canvas partial with filterable template cards. System + shared templates. One-click "Start" button. | Moderate | S3.1, S3.2 |

**New files:** `workflow_templates_controller.rb`, `_template_gallery.html.erb`, `template_gallery_controller.js`, `_template_analytics.html.erb`
**Modified files:** `workflow_template.rb`, `workflow_template_loader.rb`, `routes.rb`, all `*_v2.yml` templates

---

## Sprint Dependency Graph

```
Week 1:                          Weeks 2-3:                    Weeks 3-4:
S1.1 UserEvent ──────> S1.2 Funnel ──────> S2.1 Persistence    S3.1 Duplication
                                                  |               |
S1.3 Feedback Admin                          S2.2 Guidance    S3.2 Industry Tags
S1.4 Problem Reporting                       S2.3 Observ. Table    |
                                             S2.4 Log Level   S3.3 Analytics
                                                              S3.4 Gallery
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Users abandon onboarding before completing | High | Lost signups from blast | S1.2 tracking + S2.1 persistence to detect and recover |
| Can't measure blast ROI | High | Flying blind on campaign spend | S1.1 funnel tracking is Sprint 1 priority |
| Errors in production go unnoticed | Medium | User-facing failures with no response | Custom system covers logging; alerting deferred (accepted risk) |
| Template system too rigid for verticals | Medium | Low template adoption | S3.1-S3.4 adds duplication + gallery + industry matching |
| Noisy production logs obscure real issues | Low-Medium | Slower incident response | S2.4 one-line fix |

---

## Verification Checklist

After each sprint, validate:

- [ ] `rails test` — all existing tests pass
- [ ] `rails db:migrate` — migrations run cleanly
- [ ] New user signup -> complete onboarding -> verify `UserEvent` records created
- [ ] Admin dashboard -> new feedback view renders with real data
- [ ] Thumbs-down in chat -> comment textarea appears -> comment saved to DB
- [ ] Close browser mid-onboarding -> reopen -> resume from last step (Sprint 2)
- [ ] Post-onboarding quick actions reflect feature selections (Sprint 2)
- [ ] Duplicate a system template -> verify entity-scoped copy (Sprint 3)
- [ ] Template gallery canvas loads with filter/search (Sprint 3)
