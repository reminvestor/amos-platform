# PR #39 - User Event Tracking - Test Plan

## Overview
This PR adds user event tracking infrastructure for analytics and funnel analysis.

## Components Added
- **EventTrackable Concern** - Controller mixin for tracking events
- **UserEvent Model** - Database model with analytics methods
- **TrackUserEventJob** - Background job for async tracking
- **Database Table** - `user_events` with indexes

## Manual Testing Checklist

### Database Setup
- [ ] Run migrations: `rails db:migrate`
- [ ] Verify `user_events` table exists
- [ ] Verify indexes are created (entity_id, user_id, event_name, event_category)

### Model Testing
- [ ] Create a user event manually in console
- [ ] Verify validations (event_name required, event_category in allowed list)
- [ ] Test scopes:
  - [ ] `UserEvent.for_category('onboarding')`
  - [ ] `UserEvent.for_event('page_view')`
  - [ ] `UserEvent.recent`
  - [ ] `UserEvent.in_period(7.days.ago, Time.now)`

### Analytics Methods
- [ ] Test `UserEvent.conversion_rate('signup_started', 'signup_completed')`
- [ ] Test `UserEvent.by_cohort(7.days.ago, Time.now)`
- [ ] Verify results make sense with sample data

### Background Job
- [ ] Enqueue `TrackUserEventJob.perform_later(...)`
- [ ] Verify event is created in database after job runs
- [ ] Test error handling (invalid data)

### Controller Integration (EventTrackable)
- [ ] Include concern in a test controller
- [ ] Call `track_event('test_event', category: 'feature')`
- [ ] Verify job is enqueued
- [ ] Verify session_id, referrer, user_agent are captured

### Event Categories
Verify all valid categories work:
- [ ] `onboarding`
- [ ] `navigation`
- [ ] `feature`
- [ ] `conversion`
- [ ] `billing`
- [ ] Invalid category should fail validation

### Properties Storage
- [ ] Store arbitrary JSON properties
- [ ] Retrieve and query properties
- [ ] Test with nested JSON structures

### Edge Cases
- [ ] Event without a user (anonymous tracking)
- [ ] Event without an entity
- [ ] Concurrent events from same user
- [ ] Very long event names
- [ ] Special characters in properties

## Integration Testing

### Scenario 1: User Onboarding Flow
1. Track `onboarding_started` when user visits signup page
2. Track `onboarding_step_1` when user fills first form
3. Track `onboarding_completed` when user finishes
4. Calculate conversion rate from started → completed

### Scenario 2: Feature Usage Tracking
1. User clicks a feature button
2. Event tracked with properties: `{ feature_name: 'email_campaign', action: 'create' }`
3. Verify event appears in recent events
4. Query events by feature_name

### Scenario 3: Funnel Analysis
1. Create sample events for 10 users (varied completion rates)
2. Calculate conversion at each step
3. Identify drop-off points
4. Export data for analysis

## Performance Testing
- [ ] Insert 1000 events rapidly
- [ ] Query performance with large dataset
- [ ] Index effectiveness on filtered queries
- [ ] Background job processing speed

## Expected Results
- ✅ All validations work correctly
- ✅ Events are tracked asynchronously
- ✅ Analytics methods return accurate data
- ✅ No performance degradation with concurrent events
- ✅ Proper error handling and logging
