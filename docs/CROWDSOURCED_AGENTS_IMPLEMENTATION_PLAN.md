# Crowdsourced Agents Implementation Plan

**Status:** Phase 1 Complete - Foundation Built  
**Branch:** `feature/crowdsourced-agents`  
**Last Updated:** December 6, 2025

## Phase 1 Completed Items ✅

- [x] Database migrations for publication fields on AgentPlugin and Integration
- [x] Database migration for user_feedbacks table
- [x] Reviewable concern for shared publication workflow
- [x] AgentSecurityCheckService for AI-based agent security audits
- [x] UserFeedback model with reputation integration
- [x] TieredDiscoveryService updated with reputation ranking
- [x] AgentFactory updated with security checks and publication workflow
- [x] Feedback API endpoint (POST/GET/DELETE /api/v1/feedbacks)
- [x] Feedback UI component (Stimulus controller + Bootstrap partial)
- [x] Tool response format audit (consistent pattern confirmed)

## Remaining Tasks

- [ ] Run migrations in dev/prod environments
- [ ] Add feedback buttons to Scout chat interface
- [ ] Create admin UI for reviewing pending agents
- [ ] Implement notification system for publication approvals/rejections
- [ ] Create agent marketplace browsing UI
- [ ] Add "Publish to Marketplace" button to agent edit page

---

## Overview

This document outlines the plan to enable crowdsourced agents in the AMOS platform. The goal is to allow users to create agents that can be published and shared with other users, while maintaining quality and security through reputation systems and review processes.

## Vision: Scout as Chief of Staff

Scout remains the single point of contact for users. Instead of accumulating tools, Scout primarily delegates to specialist agents. New capabilities = new agents, not new tools for Scout.

```
USER ←→ SCOUT (Chief of Staff) ←→ AGENT NETWORK
              │
              ├── Minimal tools (data queries, canvas, delegation)
              ├── Primary job: Find best agent, delegate, report back
              └── Personality stays consistent throughout
```

---

## Current State Analysis

### Factory Comparison

| Factory | Security Review | Public Flag | Status/Lifecycle | Reputation |
|---------|-----------------|-------------|------------------|------------|
| **ToolFactory** | ✅ AI-based `SecurityCheckService` | ✅ `is_public` | ❌ Simple | ❌ None |
| **AgentFactory** | ❌ None | ❌ None | ✅ Rich lifecycle | ✅ Energy economy |
| **IntegrationFactory** | ⚠️ URL validation | ❌ None | ⚠️ `is_verified` | ❌ None |

### Existing Strengths
- Tool security review via `SecurityCheckService` (AI-based pass/review/fail)
- Agent energy economy provides natural quality signals
- Agent ELO rating and success rates exist
- Vector-based semantic search for discovery
- Ownership tracking (`user_id`, `entity_id`) on all factories

### Gaps for Crowdsourcing
1. Agents have no security review
2. Agents have no `is_public` flag or publication workflow
3. Reputation data exists but isn't used in discovery ranking
4. No tier prioritization (system → entity → public)

---

## Implementation Plan

### Phase 1: Database Schema Updates

#### Migration: Add Publication Fields to AgentPlugin

```ruby
# Fields to add to agent_plugins table
is_public: boolean, default: false
publish_status: string, default: 'private'  # private, pending_review, approved, rejected
published_at: datetime, null: true
security_rating: string, null: true  # pass, review, fail
security_reason: text, null: true
review_notes: text, null: true
reviewed_by_id: bigint, null: true (references users)
reviewed_at: datetime, null: true
usage_count: integer, default: 0  # Track how often agent is used
```

#### Migration: Add Publication Fields to Integration

```ruby
# Fields to add to integrations table
is_public: boolean, default: false
publish_status: string, default: 'private'
published_at: datetime, null: true
reviewed_by_id: bigint, null: true
reviewed_at: datetime, null: true
usage_count: integer, default: 0
```

### Phase 2: Security Review Service for Agents

#### Create AgentSecurityCheckService

Evaluate agent system prompts and tool access for security risks:

**Check for:**
- Prompt injection patterns (jailbreaks, ignore instructions)
- Data exfiltration attempts (asking for credentials, PII)
- Excessive tool access (requesting admin-only tools)
- Cost attack patterns (infinite loops, expensive operations)
- Cross-tenant data access attempts

**Rating:**
- `pass` - Safe to use
- `review` - Needs manual review, potentially risky patterns
- `fail` - Blocked, clear security violations

### Phase 3: Reviewable Concern

Create a shared module for publication workflow:

```ruby
# app/models/concerns/reviewable.rb
module Reviewable
  extend ActiveSupport::Concern
  
  included do
    belongs_to :reviewed_by, class_name: 'User', optional: true
    
    scope :public_approved, -> { where(is_public: true, publish_status: 'approved') }
    scope :pending_review, -> { where(publish_status: 'pending_review') }
    scope :private_only, -> { where(is_public: false) }
    
    enum publish_status: {
      private: 'private',
      pending_review: 'pending_review', 
      approved: 'approved',
      rejected: 'rejected'
    }, _prefix: :publish
  end
  
  def request_publication!
    # Trigger security review and set to pending
  end
  
  def approve_publication!(reviewer)
    # Admin approves for public use
  end
  
  def reject_publication!(reviewer, reason)
    # Admin rejects with reason
  end
  
  def reputation_score
    # Calculate reputation from usage metrics
  end
end
```

Apply to: `AgentPlugin`, `ToolDefinition`, `Integration`

### Phase 4: Update Discovery with Reputation

#### Update TieredDiscoveryService

Add reputation-based ranking:

```ruby
# New constants
REPUTATION_BOOST = 0.25
MIN_REPUTATION_FOR_PUBLIC = 0.3  # Public agents need minimum reputation to surface

# New method
def reputation_score(agent)
  return 0.0 unless agent.energy_state
  
  elo_factor = (agent.energy_state.elo_rating - 800) / 400.0
  success_factor = agent.energy_state.success_rate
  usage_factor = [agent.usage_count / 1000.0, 0.15].min
  
  (elo_factor * 0.4 + success_factor * 0.45 + usage_factor * 0.15).clamp(0, 1)
end

# Updated discovery priority
def discover_agents(prompt:, limit:)
  agents = AgentPlugin.active.search_by_similarity(prompt, limit: limit * 3)
  
  prioritized = agents.map do |agent|
    score = 1.0 - (agent.neighbor_distance || 0.5)
    
    # Tier 1: User's own agents (highest priority)
    score += 0.4 if agent.user_id == @user&.id
    
    # Tier 2: Entity-specific agents
    score += 0.3 if agent.entity_id == @entity&.id && agent.user_id != @user&.id
    
    # Tier 3: System agents (nil entity, nil user)
    score += 0.25 if agent.system_agent? && agent.system_wide?
    
    # Tier 4: Public approved agents (with reputation filter)
    if agent.is_public && agent.publish_approved?
      rep = reputation_score(agent)
      if rep >= MIN_REPUTATION_FOR_PUBLIC
        score += rep * REPUTATION_BOOST
      else
        score -= 0.2  # Penalty for low-reputation public agents
      end
    end
    
    # Security penalty
    score -= 0.5 if agent.security_rating == 'fail'
    score -= 0.1 if agent.security_rating == 'review'
    
    { agent: agent, score: score }
  end
  
  prioritized.sort_by { |a| -a[:score] }.first(limit)
end
```

### Phase 5: Admin Review Interface

#### Add Admin Controller for Reviews

```ruby
# app/controllers/admin/agent_reviews_controller.rb
class Admin::AgentReviewsController < Admin::BaseController
  def index
    @pending_agents = AgentPlugin.pending_review.includes(:user, :entity)
    @pending_tools = ToolDefinition.where(is_public: true, security_rating: 'review')
  end
  
  def approve
    @agent = AgentPlugin.find(params[:id])
    @agent.approve_publication!(current_user)
    redirect_to admin_agent_reviews_path, notice: "Agent approved"
  end
  
  def reject
    @agent = AgentPlugin.find(params[:id])
    @agent.reject_publication!(current_user, params[:reason])
    redirect_to admin_agent_reviews_path, notice: "Agent rejected"
  end
end
```

### Phase 6: Update Agent Factory

#### Add Security Check to AgentFactory

```ruby
# In Factories::AgentFactory#create
def create(params)
  # ... existing validation ...
  
  # Step 6: Security check (before test execution)
  if params[:is_public] || params[:request_publication]
    security_result = run_security_check(agent)
    agent.update!(
      security_rating: security_result['rating'],
      security_reason: security_result['reason']
    )
    
    if security_result['rating'] == 'fail'
      raise SecurityError, "Agent failed security review: #{security_result['reason']}"
    end
  end
  
  # ... rest of creation ...
end

def run_security_check(agent)
  AgentSecurityCheckService.new.evaluate(agent)
end
```

### Phase 7: Track Usage for Reputation

#### Add Usage Tracking

```ruby
# In delegate_to_agent tool or agent execution
def track_agent_usage(agent)
  agent.increment!(:usage_count)
  
  # Also track in entity-specific analytics
  AgentUsageMetric.create!(
    agent_plugin: agent,
    entity: @entity,
    user: @user,
    used_at: Time.current
  )
end
```

---

## File Changes Summary

### New Files
- `app/models/concerns/reviewable.rb`
- `app/services/agent_security_check_service.rb`
- `app/controllers/admin/agent_reviews_controller.rb`
- `app/views/admin/agent_reviews/` (index, show)
- `db/migrate/XXXXXX_add_publication_fields_to_agent_plugins.rb`
- `db/migrate/XXXXXX_add_publication_fields_to_integrations.rb`

### Modified Files
- `app/models/agent_plugin.rb` - Add `Reviewable` concern
- `app/models/tool_definition.rb` - Add `Reviewable` concern (refactor existing)
- `app/models/integration.rb` - Add `Reviewable` concern
- `app/services/tiered_discovery_service.rb` - Add reputation ranking
- `app/services/factories/agent_factory.rb` - Add security check
- `app/services/tools/delegate_to_agent_tool.rb` - Add usage tracking
- `config/routes.rb` - Add admin review routes

---

## Testing Plan

### Unit Tests
- `AgentSecurityCheckService` - Test various prompt patterns
- `Reviewable` concern - Test publication workflow
- `TieredDiscoveryService` - Test reputation ranking

### Integration Tests
- Full publication workflow (create → request → review → approve)
- Discovery prioritization (verify tier ordering)
- Security rejection flow

### Manual Testing
- Create agent as user, request publication
- Admin reviews and approves/rejects
- Verify agent appears in discovery for other users
- Verify reputation affects ranking

---

## Rollout Plan

### Phase 1: Foundation (This PR)
- [ ] Database migrations
- [ ] Reviewable concern
- [ ] AgentSecurityCheckService
- [ ] Update AgentFactory

### Phase 2: Discovery (Next PR)
- [ ] Update TieredDiscoveryService with reputation
- [ ] Add usage tracking
- [ ] Test discovery ranking

### Phase 3: Admin UI (Following PR)
- [ ] Admin review interface
- [ ] Review queue notifications
- [ ] Bulk approve/reject

### Phase 4: User-Facing (Final PR)
- [ ] "Publish Agent" button in UI
- [ ] Public agent marketplace/browser
- [ ] Agent ratings/reviews (future consideration)

---

---

## Phase 8: Success/Failure Tracking Audit & User Feedback

### Current State Analysis

#### Execution Tracking Models (Inconsistent)

| Model | Status Values | Has `mark_completed!` | Has `mark_failed!` | Quality Tracking |
|-------|---------------|----------------------|-------------------|------------------|
| `AgentPluginExecution` | running, completed, failed, waiting_for_input, cancelled | ✅ | ✅ | ❌ |
| `AgentExecution` | pending, running, completed, failed | ✅ `complete!` | ✅ `fail!` | ❌ |
| `AgentToolExecution` | pending, running, success, error | ❌ | ❌ | ✅ `result_met_expectations`, `execution_quality_score` |
| `WorkflowStepExecution` | pending, running, completed, failed | ✅ | ✅ | ❌ |
| `ScheduledTaskRun` | pending, running, completed, failed | ✅ `complete!` | ✅ `fail!` | ❌ |

#### Tool Execution Success Pattern

Tools return `{ success: true/false, ... }` but this is inconsistent:
- Some tools return `{ success: true, data: ... }`
- Some return `{ error: "message" }` (no `success` key)
- Some return raw data without success indicator

**Problem:** No standardized way to determine if a tool call succeeded.

#### Missing: User Feedback Loop

Currently:
- ✅ System tracks execution success/failure (did it run without error?)
- ❌ No user feedback (was the result actually helpful?)
- ❌ No way for users to rate agent responses
- ❌ Reputation is purely based on technical success, not user satisfaction

### Proposed User Feedback System

#### Migration: Add Feedback Table

```ruby
# db/migrate/XXXXXX_create_user_feedback.rb
create_table :user_feedbacks do |t|
  t.references :user, null: false, foreign_key: true
  t.references :entity, null: false, foreign_key: true
  
  # What are they rating?
  t.string :feedbackable_type, null: false  # AgentPluginExecution, ScheduledTaskRun, etc.
  t.bigint :feedbackable_id, null: false
  
  # The feedback
  t.integer :rating, null: false  # -1 (thumbs down), 0 (neutral), 1 (thumbs up)
  t.text :comment  # Optional comment
  t.string :feedback_type  # 'accuracy', 'helpfulness', 'speed', 'overall'
  
  # Context
  t.string :session_id
  t.jsonb :metadata, default: {}
  
  t.timestamps
  
  t.index [:feedbackable_type, :feedbackable_id]
  t.index [:user_id, :created_at]
end
```

#### Model: UserFeedback

```ruby
# app/models/user_feedback.rb
class UserFeedback < ApplicationRecord
  belongs_to :user
  belongs_to :entity
  belongs_to :feedbackable, polymorphic: true
  
  validates :rating, inclusion: { in: [-1, 0, 1] }
  validates :feedbackable_type, inclusion: { 
    in: %w[AgentPluginExecution ScheduledTaskRun ScoutMessage] 
  }
  
  scope :positive, -> { where(rating: 1) }
  scope :negative, -> { where(rating: -1) }
  scope :for_agent, ->(agent) { 
    where(feedbackable_type: 'AgentPluginExecution')
      .joins("INNER JOIN agent_plugin_executions ON user_feedbacks.feedbackable_id = agent_plugin_executions.id")
      .where(agent_plugin_executions: { agent_plugin_id: agent.id })
  }
  
  after_create :update_agent_reputation
  
  private
  
  def update_agent_reputation
    return unless feedbackable_type == 'AgentPluginExecution'
    
    execution = feedbackable
    agent = execution.agent_plugin
    
    # Update energy state based on feedback
    if agent.energy_state
      case rating
      when 1  # Thumbs up
        agent.energy_state.earn!(2.0, reason: 'user_positive_feedback')
      when -1  # Thumbs down  
        agent.energy_state.penalize!(3.0, reason: 'user_negative_feedback')
      end
    end
  end
end
```

#### Add to AgentPlugin for Reputation

```ruby
# In AgentPlugin
has_many :feedbacks, through: :agent_plugin_executions, source: :user_feedbacks

def user_satisfaction_score
  total = feedbacks.count
  return 0.5 if total < 5  # Not enough data
  
  positive = feedbacks.positive.count
  negative = feedbacks.negative.count
  
  # Score from 0 to 1
  (positive.to_f / (positive + negative)).clamp(0, 1)
rescue ZeroDivisionError
  0.5
end

def combined_reputation_score
  energy_score = energy_state&.success_rate || 0.5
  user_score = user_satisfaction_score
  elo_score = ((energy_state&.elo_rating || 1000) - 800) / 400.0
  
  # Weight: 40% technical success, 40% user satisfaction, 20% ELO
  (energy_score * 0.4 + user_score * 0.4 + elo_score.clamp(0, 1) * 0.2)
end
```

### Standardize Tool Success/Failure

#### Create Tool Response Standard

```ruby
# app/services/tools/base_tool.rb - Update success_response and error_response

def success_response(**data)
  {
    success: true,
    tool: self.class.metadata[:name],
    timestamp: Time.current.iso8601,
    **data
  }
end

def error_response(message, **data)
  {
    success: false,
    error: message,
    tool: self.class.metadata[:name],
    timestamp: Time.current.iso8601,
    **data
  }
end
```

#### Audit and Fix Inconsistent Tools

Tools to audit for consistent response format:
- [ ] All tools in `app/services/tools/` return `success_response` or `error_response`
- [ ] Remove tools that return raw data without success wrapper
- [ ] Update `ToolCatalog.execute_tool` to normalize responses

### UI Component: Feedback Buttons

```erb
<%# app/views/shared/_feedback_buttons.html.erb %>
<div class="feedback-buttons" data-feedbackable-type="<%= feedbackable_type %>" data-feedbackable-id="<%= feedbackable_id %>">
  <button class="btn btn-sm btn-outline-success feedback-btn" data-rating="1" title="Helpful">
    <i class="bi bi-hand-thumbs-up"></i>
  </button>
  <button class="btn btn-sm btn-outline-danger feedback-btn" data-rating="-1" title="Not helpful">
    <i class="bi bi-hand-thumbs-down"></i>
  </button>
</div>
```

#### API Endpoint

```ruby
# app/controllers/api/v1/feedbacks_controller.rb
class Api::V1::FeedbacksController < Api::V1::BaseController
  def create
    @feedback = current_user.user_feedbacks.build(feedback_params)
    @feedback.entity = current_entity
    
    if @feedback.save
      render json: { success: true, feedback_id: @feedback.id }
    else
      render json: { success: false, errors: @feedback.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  private
  
  def feedback_params
    params.require(:feedback).permit(:feedbackable_type, :feedbackable_id, :rating, :comment, :feedback_type, :session_id)
  end
end
```

---

## Updated File Changes Summary

### New Files (Additional)
- `app/models/user_feedback.rb`
- `app/controllers/api/v1/feedbacks_controller.rb`
- `app/views/shared/_feedback_buttons.html.erb`
- `app/javascript/controllers/feedback_controller.js`
- `db/migrate/XXXXXX_create_user_feedbacks.rb`

### Files to Audit/Update
- All `app/services/tools/*_tool.rb` - Standardize response format
- `app/services/tools/base_tool.rb` - Enforce response standard

---

## Success Metrics

- Number of public agents approved
- Usage distribution (are good agents being discovered?)
- Security incidents (should be zero)
- Discovery relevance (user feedback on agent suggestions)
- Agent creator engagement (do users want to publish?)
- **User satisfaction scores** (thumbs up/down ratio)
- **Feedback submission rate** (are users engaging with feedback?)
- **Correlation between technical success and user satisfaction**

---

## Open Questions

1. **Should public agents earn revenue share?** - Future consideration for monetization
2. **Should we allow agent "forking"?** - Copy and modify public agents
3. **Rate limiting for public agents?** - Prevent abuse of popular agents
4. **Agent versioning for public agents?** - Updates require re-review?

---

## References

- `app/services/security_check_service.rb` - Existing tool security review
- `app/models/tool_definition.rb` - Existing `is_public` implementation
- `app/services/tiered_discovery_service.rb` - Current discovery logic
- `app/models/agent_plugin.rb` - Agent model with energy/ELO

