# PR #38 - Feedback Admin Dashboard - Test Plan

## Overview
This PR adds an admin dashboard for viewing and analyzing user feedback with negative comment tracking.

## Components Added
- **Admin::FeedbacksController** - Dashboard with analytics and filtering
- **Feedback buttons partial** - UI component for collecting feedback (JS already exists)
- **View** - `/admin/feedbacks` dashboard with charts and stats

## Manual Testing Checklist

### Admin Dashboard Access
- [ ] Navigate to `/admin/feedbacks`
- [ ] Verify page loads without errors
- [ ] Verify date range defaults to last 30 days

### Statistics Cards
- [ ] Total Feedback count displays correctly
- [ ] Satisfaction Score shows percentage (0-100%)
- [ ] Satisfaction badge color changes based on score (green ≥70%, yellow ≥40%, red <40%)
- [ ] Positive count and percentage display
- [ ] Negative count and percentage display
- [ ] With Comments count and percentage display

### Date Range Filtering
- [ ] Change start date and submit - results update
- [ ] Change end date and submit - results update
- [ ] Click "Reset" - returns to default (last 30 days)
- [ ] Invalid dates handled gracefully

### Daily Trend Chart
- [ ] Chart.js chart loads correctly
- [ ] Positive feedback line displays in green
- [ ] Negative feedback line displays in red
- [ ] Hovering shows tooltips with exact counts
- [ ] X-axis shows dates correctly
- [ ] Y-axis shows integer step sizes

### Feedback by Type Table
- [ ] Table shows all feedbackable types with count
- [ ] Satisfaction score per type calculated correctly
- [ ] Color coding works (green/yellow/red based on score)
- [ ] Empty state shows when no data

### Recent Negative Comments Section
- [ ] Shows up to 20 most recent negative feedbacks with comments
- [ ] User email displays (or "Unknown User")
- [ ] Feedbackable type shows (humanized)
- [ ] Comment text truncated to 300 chars
- [ ] Time ago displays correctly ("X minutes ago")
- [ ] Empty state shows when no negative comments

### Recent Feedback Table
- [ ] Shows up to 50 most recent feedbacks
- [ ] Rating badge displays correctly (Positive/Negative/Neutral)
- [ ] User email shows
- [ ] Feedbackable type displays
- [ ] Comment column shows text or "--" if empty
- [ ] Date formatted correctly
- [ ] Table scrolls horizontally on mobile

### Performance
- [ ] Dashboard loads in <2 seconds with 1000+ feedback records
- [ ] Date filtering responds quickly
- [ ] Chart renders smoothly

## Integration Testing Scenarios

### Scenario 1: New Admin Views Dashboard
1. Create sample feedback data (mix of positive/negative, with/without comments)
2. Admin navigates to `/admin/feedbacks`
3. Verify all stats are calculated correctly
4. Verify chart shows daily breakdown

### Scenario 2: Filter by Date Range
1. Create feedback over a 60-day period
2. Filter to last 7 days
3. Verify only recent feedback shows
4. Verify stats recalculate for new range

### Scenario 3: Negative Feedback Tracking
1. User submits negative feedback with comment "Feature is broken"
2. Admin views dashboard
3. Comment appears in "Recent Negative Feedback" section
4. Verify user and timestamp are correct

## Expected Results
- ✅ All analytics calculate correctly
- ✅ Charts render properly
- ✅ Date filtering works as expected
- ✅ No N+1 queries (uses includes for associations)
- ✅ Responsive on mobile devices
