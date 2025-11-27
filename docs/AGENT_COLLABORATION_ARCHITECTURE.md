# Agent Collaboration & Reinforcement Learning Architecture

## Overview

This document outlines a system where agents can collaborate by asking other agents for help, governed by an energy/reward system that encourages self-reliance while enabling collaboration when beneficial. This feeds into a broader Reinforcement Learning (RL) network that optimizes agent and tool selection.

## Core Concepts

### The Energy Model

Every agent has an **energy score** that governs their ability to collaborate:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AGENT ENERGY SYSTEM                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ENERGY SOURCES (+)                    ENERGY COSTS (-)                  │
│  ─────────────────                     ─────────────────                 │
│  • Task completion: +10-50             • Ask for help: -5                │
│  • High quality result: +20            • Delegate task: -10              │
│  • Fast completion: +5                 • Failed attempt: -3              │
│  • User satisfaction: +15              • Timeout: -5                     │
│  • Helped another agent: +8            • Retry needed: -2                │
│  • Passive regeneration: +1/hour                                         │
│                                                                          │
│  ENERGY THRESHOLDS                                                       │
│  ─────────────────────                                                   │
│  • 100+ : Can help others freely                                         │
│  • 50-99: Normal operation                                               │
│  • 20-49: Should try harder before asking                                │
│  • 1-19 : Must complete tasks solo to recover                            │
│  • 0    : Cannot ask for help, must regenerate                           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Collaboration Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    AGENT COLLABORATION FLOW                              │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  1. AGENT RECEIVES TASK                                                  │
│     "Analyze this financial report and create visualizations"           │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  2. SELF-ASSESSMENT                                                      │
│     • Do I have the skills for this? (capability match)                 │
│     • Do I have the tools needed? (tool availability)                   │
│     • How confident am I? (0-100%)                                      │
│     • What's my current energy? (collaboration budget)                  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
        ┌─────────────────────┐         ┌─────────────────────┐
        │  HIGH CONFIDENCE    │         │  LOW CONFIDENCE     │
        │  (>70%)             │         │  (<70%)             │
        ├─────────────────────┤         ├─────────────────────┤
        │ Execute solo        │         │ Consider options:   │
        │                     │         │ • Try anyway        │
        │                     │         │ • Ask for advice    │
        │                     │         │ • Delegate subtask  │
        │                     │         │ • Full delegation   │
        └─────────────────────┘         └─────────────────────┘
                    │                               │
                    │                   ┌───────────┴───────────┐
                    │                   ▼                       ▼
                    │       ┌─────────────────────┐ ┌─────────────────────┐
                    │       │  ENOUGH ENERGY?     │ │  LOW ENERGY         │
                    │       │  (>20)              │ │  (<20)              │
                    │       ├─────────────────────┤ ├─────────────────────┤
                    │       │ Can ask for help    │ │ Must try solo       │
                    │       │ or delegate         │ │ to earn energy      │
                    │       └─────────────────────┘ └─────────────────────┘
                    │                   │                       │
                    └───────────────────┴───────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  3. EXECUTION & REWARD                                                   │
│     • Complete task → earn energy based on quality                      │
│     • Help given → helper earns energy too                              │
│     • Failure → lose energy, learn from mistake                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Database Models

### AgentEnergyState

```ruby
class AgentEnergyState < ApplicationRecord
  belongs_to :agent_plugin
  belongs_to :entity
  
  # Current State
  attribute :current_energy, :float, default: 50.0
  attribute :max_energy, :float, default: 100.0
  attribute :energy_regeneration_rate, :float, default: 1.0  # per hour
  
  # Lifetime Stats
  attribute :total_energy_earned, :float, default: 0.0
  attribute :total_energy_spent, :float, default: 0.0
  attribute :tasks_completed, :integer, default: 0
  attribute :tasks_delegated, :integer, default: 0
  attribute :help_requests_made, :integer, default: 0
  attribute :help_requests_received, :integer, default: 0
  
  # Performance Metrics
  attribute :success_rate, :float, default: 0.0
  attribute :avg_task_quality, :float, default: 0.0
  attribute :avg_response_time_ms, :integer
  
  # Collaboration Stats
  attribute :collaboration_score, :float, default: 0.0  # How good at teamwork
  attribute :autonomy_score, :float, default: 0.0       # How self-sufficient
  
  # Timestamps
  attribute :last_energy_update_at, :datetime
  attribute :last_task_at, :datetime
  
  # Methods
  def can_ask_for_help?
    current_energy >= 5  # Cost of asking
  end
  
  def can_delegate?
    current_energy >= 10  # Cost of delegation
  end
  
  def should_try_solo?
    current_energy < 20  # Low energy, need to earn
  end
  
  def regenerate_energy!
    hours_since_update = (Time.current - last_energy_update_at) / 1.hour
    regenerated = hours_since_update * energy_regeneration_rate
    new_energy = [current_energy + regenerated, max_energy].min
    update!(current_energy: new_energy, last_energy_update_at: Time.current)
  end
end
```

### AgentCollaborationRequest

```ruby
class AgentCollaborationRequest < ApplicationRecord
  belongs_to :requesting_agent, class_name: 'AgentPlugin'
  belongs_to :target_agent, class_name: 'AgentPlugin', optional: true
  belongs_to :task_execution, optional: true
  belongs_to :entity
  
  # Request Details
  attribute :request_type, :string  # advice, subtask, full_delegation, review
  attribute :description, :text     # What help is needed
  attribute :context, :jsonb        # Task context, what's been tried
  attribute :urgency, :string       # low, medium, high, critical
  
  # Agent Selection
  attribute :required_capabilities, :jsonb  # Skills needed
  attribute :preferred_agents, :jsonb       # Specific agents if any
  attribute :excluded_agents, :jsonb        # Agents to avoid
  
  # Status
  attribute :status, :string, default: 'pending'  # pending, accepted, completed, rejected, expired
  attribute :accepted_by_agent_id, :integer
  attribute :accepted_at, :datetime
  attribute :completed_at, :datetime
  
  # Results
  attribute :response, :jsonb       # The help provided
  attribute :quality_rating, :float # 0-1, rated by requester
  attribute :was_helpful, :boolean
  
  # Energy Transaction
  attribute :energy_cost, :float    # What requester paid
  attribute :energy_reward, :float  # What helper earned
  
  # Timing
  attribute :timeout_at, :datetime
  attribute :created_at, :datetime
end
```

### AgentEnergyTransaction

```ruby
class AgentEnergyTransaction < ApplicationRecord
  belongs_to :agent_plugin
  belongs_to :entity
  belongs_to :related_task, class_name: 'AgentPluginExecution', optional: true
  belongs_to :collaboration_request, optional: true
  
  attribute :transaction_type, :string  # earned, spent, regenerated, bonus, penalty
  attribute :amount, :float             # Positive or negative
  attribute :reason, :string            # Description
  attribute :balance_before, :float
  attribute :balance_after, :float
  attribute :metadata, :jsonb
  
  # Types of transactions
  EARN_TYPES = %w[task_completion quality_bonus speed_bonus user_satisfaction helped_agent]
  SPEND_TYPES = %w[ask_advice delegate_subtask full_delegation]
  PENALTY_TYPES = %w[task_failure timeout retry_needed]
end
```

### AgentCapabilityProfile

```ruby
class AgentCapabilityProfile < ApplicationRecord
  belongs_to :agent_plugin
  
  # Skill Ratings (0-100, learned over time)
  attribute :capabilities, :jsonb, default: {}
  # Example: {
  #   "data_analysis": 85,
  #   "visualization": 72,
  #   "writing": 90,
  #   "coding": 65,
  #   "research": 88,
  #   "integration_apis": 45
  # }
  
  # Tool Proficiency (0-100)
  attribute :tool_proficiency, :jsonb, default: {}
  # Example: {
  #   "web_search": 95,
  #   "create_visualization": 80,
  #   "execute_integration": 60
  # }
  
  # Collaboration Traits
  attribute :helpfulness_score, :float, default: 50.0    # How good at helping
  attribute :independence_score, :float, default: 50.0   # How self-sufficient
  attribute :teaching_ability, :float, default: 50.0     # How good at explaining
  attribute :learning_rate, :float, default: 1.0         # How fast skills improve
  
  # Update capability based on task outcome
  def update_capability(skill, success:, quality: 0.5)
    current = capabilities[skill] || 50.0
    adjustment = success ? (quality * 2) : -1
    new_value = [[current + adjustment, 0].max, 100].min
    capabilities[skill] = new_value
    save!
  end
end
```

## Reinforcement Learning Network

### Task Router (RL Agent)

The Task Router is an RL agent that learns to assign tasks optimally:

```ruby
class TaskRouter
  # State: Current task features + available agents + historical performance
  # Action: Which agent(s) to assign
  # Reward: Task success, quality, speed, cost efficiency
  
  def route_task(task_description, context = {})
    # 1. Extract task features
    task_features = extract_features(task_description)
    
    # 2. Get available agents with their states
    agents = get_available_agents(context[:entity])
    
    # 3. Score each agent for this task
    agent_scores = agents.map do |agent|
      {
        agent: agent,
        capability_match: calculate_capability_match(agent, task_features),
        energy_available: agent.energy_state.current_energy,
        historical_success: get_historical_success(agent, task_features),
        current_load: agent.current_task_count,
        expected_quality: predict_quality(agent, task_features),
        expected_time: predict_completion_time(agent, task_features)
      }
    end
    
    # 4. Apply RL policy to select best agent(s)
    selected = apply_policy(agent_scores, task_features)
    
    # 5. Record decision for learning
    record_routing_decision(task_features, selected)
    
    selected
  end
  
  private
  
  def apply_policy(agent_scores, task_features)
    # Multi-armed bandit with Thompson Sampling
    # or Deep Q-Network for more complex decisions
    
    # Exploration vs Exploitation
    if should_explore?
      # Try a less-proven agent to learn
      explore_selection(agent_scores)
    else
      # Pick the best known option
      exploit_selection(agent_scores)
    end
  end
end
```

### Reward Function

```ruby
class TaskRewardCalculator
  # Calculate reward for a completed task
  def calculate(execution)
    base_reward = 10.0
    
    # Quality multiplier (0.5 - 2.0)
    quality_score = evaluate_quality(execution)
    quality_multiplier = 0.5 + (quality_score * 1.5)
    
    # Speed bonus (0 - 10)
    speed_bonus = calculate_speed_bonus(execution)
    
    # User satisfaction (0 - 15)
    satisfaction_bonus = execution.user_rating.present? ? 
      (execution.user_rating / 5.0) * 15 : 0
    
    # Collaboration efficiency
    collab_bonus = calculate_collaboration_bonus(execution)
    
    # Penalties
    penalties = calculate_penalties(execution)
    
    total = (base_reward * quality_multiplier) + 
            speed_bonus + 
            satisfaction_bonus + 
            collab_bonus - 
            penalties
    
    [total, 0].max  # Never negative
  end
  
  private
  
  def calculate_speed_bonus(execution)
    expected_time = execution.agent_plugin.avg_completion_time
    actual_time = execution.duration_ms
    
    if actual_time < expected_time * 0.5
      10  # Much faster than expected
    elsif actual_time < expected_time * 0.8
      5   # Faster than expected
    else
      0
    end
  end
  
  def calculate_collaboration_bonus(execution)
    # Bonus for efficient collaboration
    if execution.collaboration_requests.any?
      helpful_collabs = execution.collaboration_requests.where(was_helpful: true)
      (helpful_collabs.count * 3) - (execution.collaboration_requests.count * 1)
    else
      2  # Small bonus for independence
    end
  end
  
  def calculate_penalties(execution)
    penalty = 0
    penalty += 3 if execution.failed?
    penalty += 2 if execution.retried?
    penalty += 5 if execution.timed_out?
    penalty
  end
end
```

## Collaboration Protocol

### Asking for Help

```ruby
class AgentCollaborationService
  def request_help(requesting_agent, request_type:, description:, context: {})
    energy_state = requesting_agent.energy_state
    
    # Check if agent can afford to ask
    cost = energy_cost_for(request_type)
    unless energy_state.current_energy >= cost
      return {
        success: false,
        error: "Insufficient energy (#{energy_state.current_energy}/#{cost} needed)",
        suggestion: "Complete more tasks solo to earn energy"
      }
    end
    
    # Find suitable agents to help
    candidates = find_helper_candidates(
      requesting_agent: requesting_agent,
      required_capabilities: extract_capabilities(description),
      request_type: request_type
    )
    
    if candidates.empty?
      return {
        success: false,
        error: "No suitable agents available",
        suggestion: "Try breaking down the task or attempting solo"
      }
    end
    
    # Create collaboration request
    request = AgentCollaborationRequest.create!(
      requesting_agent: requesting_agent,
      request_type: request_type,
      description: description,
      context: context,
      energy_cost: cost,
      timeout_at: 5.minutes.from_now
    )
    
    # Deduct energy
    energy_state.spend_energy!(cost, reason: "collaboration_request", request: request)
    
    # Route to best available helper
    helper = select_best_helper(candidates, request)
    request.update!(target_agent: helper, status: 'pending')
    
    # Notify helper agent
    notify_agent(helper, request)
    
    { success: true, request: request, helper: helper }
  end
  
  def respond_to_help_request(helper_agent, request, response:)
    return { error: "Request expired" } if request.expired?
    return { error: "Already handled" } unless request.pending?
    
    request.update!(
      accepted_by_agent_id: helper_agent.id,
      accepted_at: Time.current,
      status: 'in_progress'
    )
    
    # Helper provides assistance
    result = helper_agent.provide_help(request, response)
    
    # Complete the request
    request.update!(
      status: 'completed',
      completed_at: Time.current,
      response: result
    )
    
    # Reward helper
    reward = calculate_helper_reward(request)
    helper_agent.energy_state.earn_energy!(reward, reason: "helped_agent", request: request)
    
    { success: true, result: result }
  end
  
  private
  
  def energy_cost_for(request_type)
    case request_type
    when 'advice'        then 5
    when 'review'        then 5
    when 'subtask'       then 10
    when 'full_delegation' then 15
    else 5
    end
  end
  
  def find_helper_candidates(requesting_agent:, required_capabilities:, request_type:)
    AgentPlugin.active
      .where.not(id: requesting_agent.id)
      .joins(:energy_state)
      .where('agent_energy_states.current_energy >= ?', 10)  # Must have energy to help
      .select { |agent| agent.can_help_with?(required_capabilities) }
      .sort_by { |agent| -agent.capability_profile.helpfulness_score }
  end
end
```

### Collaboration Types

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      COLLABORATION TYPES                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ADVICE (Cost: 5 energy)                                                │
│  ───────────────────────                                                │
│  • Quick question/answer                                                 │
│  • "How should I approach this?"                                        │
│  • Helper provides guidance, requester executes                         │
│  • Helper reward: 3-8 energy based on helpfulness                       │
│                                                                          │
│  REVIEW (Cost: 5 energy)                                                │
│  ───────────────────────                                                │
│  • Check work before submitting                                         │
│  • "Does this look right?"                                              │
│  • Helper validates and suggests improvements                           │
│  • Helper reward: 3-8 energy                                            │
│                                                                          │
│  SUBTASK (Cost: 10 energy)                                              │
│  ─────────────────────────                                              │
│  • Delegate a portion of the work                                       │
│  • "Can you handle the data analysis part?"                             │
│  • Helper completes subtask, requester integrates                       │
│  • Helper reward: 8-15 energy                                           │
│                                                                          │
│  FULL DELEGATION (Cost: 15 energy)                                      │
│  ─────────────────────────────────                                      │
│  • Hand off entire task                                                  │
│  • "I'm not equipped for this, can you take over?"                      │
│  • Helper takes full ownership                                          │
│  • Helper reward: 15-30 energy (gets task completion bonus)             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Agent Decision Making

### Should I Ask for Help?

```ruby
class AgentDecisionEngine
  def should_ask_for_help?(agent, task)
    # Factors to consider
    confidence = agent.estimate_confidence(task)
    energy = agent.energy_state.current_energy
    task_complexity = estimate_complexity(task)
    time_pressure = task.urgent?
    
    # Decision matrix
    decision_score = 0
    
    # Low confidence increases desire to ask
    decision_score += (100 - confidence) * 0.5
    
    # High complexity increases desire to ask
    decision_score += task_complexity * 0.3
    
    # Time pressure increases desire to ask
    decision_score += 20 if time_pressure
    
    # Low energy discourages asking (need to earn)
    decision_score -= (50 - energy) * 0.5 if energy < 50
    
    # Check if asking makes sense
    should_ask = decision_score > 40 && energy >= 5
    
    {
      should_ask: should_ask,
      confidence: confidence,
      decision_score: decision_score,
      energy_available: energy,
      recommendation: generate_recommendation(should_ask, confidence, energy)
    }
  end
  
  private
  
  def generate_recommendation(should_ask, confidence, energy)
    if energy < 5
      "Complete tasks solo to regenerate energy before asking for help"
    elsif confidence > 80
      "You've got this! Execute with confidence"
    elsif should_ask
      "Consider asking for advice or delegating a subtask"
    else
      "Try your best first - you'll learn and earn energy"
    end
  end
end
```

## Learning & Adaptation

### Capability Learning

```ruby
class CapabilityLearner
  # Update agent capabilities based on task outcomes
  def learn_from_execution(execution)
    agent = execution.agent_plugin
    profile = agent.capability_profile
    
    # Extract skills used in this task
    skills_used = extract_skills(execution.task_description)
    
    # Update each skill based on outcome
    skills_used.each do |skill|
      profile.update_capability(
        skill,
        success: execution.successful?,
        quality: execution.quality_score || 0.5
      )
    end
    
    # Update tool proficiency
    execution.tools_used.each do |tool_name|
      profile.update_tool_proficiency(
        tool_name,
        success: execution.successful?
      )
    end
    
    # Update collaboration traits
    if execution.collaboration_requests.any?
      update_collaboration_traits(profile, execution)
    end
  end
  
  private
  
  def update_collaboration_traits(profile, execution)
    requests = execution.collaboration_requests
    
    # If agent asked for help effectively
    helpful_requests = requests.where(was_helpful: true)
    if helpful_requests.any?
      # Good at knowing when to ask
      profile.independence_score = [profile.independence_score - 1, 0].max
    end
    
    # If agent helped others
    if execution.helped_with_requests.any?
      profile.helpfulness_score = [profile.helpfulness_score + 2, 100].min
    end
  end
end
```

### RL Policy Updates

```ruby
class PolicyUpdater
  # Update routing policy based on outcomes
  def update_from_execution(execution)
    routing_decision = execution.routing_decision
    return unless routing_decision
    
    # Calculate reward
    reward = TaskRewardCalculator.new.calculate(execution)
    
    # Update Q-values or policy network
    update_policy(
      state: routing_decision.state_features,
      action: routing_decision.selected_agent_id,
      reward: reward,
      next_state: get_current_state
    )
    
    # Update exploration rate (decay over time)
    decay_exploration_rate
  end
  
  private
  
  def update_policy(state:, action:, reward:, next_state:)
    # Simple Q-learning update
    # Q(s,a) = Q(s,a) + α * (r + γ * max(Q(s',a')) - Q(s,a))
    
    learning_rate = 0.1
    discount_factor = 0.95
    
    current_q = get_q_value(state, action)
    max_next_q = get_max_q_value(next_state)
    
    new_q = current_q + learning_rate * (reward + discount_factor * max_next_q - current_q)
    
    set_q_value(state, action, new_q)
  end
end
```

## Limits & Safeguards

### Collaboration Limits

```ruby
class CollaborationLimits
  # Per-agent limits
  MAX_HELP_REQUESTS_PER_HOUR = 10
  MAX_DELEGATIONS_PER_HOUR = 5
  MAX_CONCURRENT_COLLABORATIONS = 3
  
  # Per-entity limits
  MAX_TOTAL_COLLABORATIONS_PER_HOUR = 50
  
  # Depth limits (prevent infinite chains)
  MAX_DELEGATION_DEPTH = 3  # A can delegate to B, B to C, C to D, stop
  
  def can_request_collaboration?(agent, request_type)
    # Check hourly limits
    recent_requests = agent.collaboration_requests
      .where('created_at > ?', 1.hour.ago)
    
    return false if recent_requests.count >= MAX_HELP_REQUESTS_PER_HOUR
    
    if request_type == 'full_delegation'
      delegations = recent_requests.where(request_type: 'full_delegation')
      return false if delegations.count >= MAX_DELEGATIONS_PER_HOUR
    end
    
    # Check concurrent limit
    active = agent.collaboration_requests.where(status: ['pending', 'in_progress'])
    return false if active.count >= MAX_CONCURRENT_COLLABORATIONS
    
    true
  end
  
  def check_delegation_depth(request)
    depth = 0
    current = request
    
    while current.parent_request.present?
      depth += 1
      return false if depth >= MAX_DELEGATION_DEPTH
      current = current.parent_request
    end
    
    true
  end
end
```

### Circuit Breakers

```ruby
class CollaborationCircuitBreaker
  # Prevent collaboration storms
  
  def check_entity_health(entity)
    recent_collabs = AgentCollaborationRequest
      .where(entity: entity)
      .where('created_at > ?', 1.hour.ago)
    
    if recent_collabs.count > CollaborationLimits::MAX_TOTAL_COLLABORATIONS_PER_HOUR
      # Trip the circuit breaker
      trip_breaker!(entity, reason: "Too many collaborations")
      return false
    end
    
    # Check for collaboration loops
    if detect_collaboration_loop?(entity)
      trip_breaker!(entity, reason: "Collaboration loop detected")
      return false
    end
    
    true
  end
  
  def detect_collaboration_loop?(entity)
    # Detect A -> B -> C -> A patterns
    recent = AgentCollaborationRequest
      .where(entity: entity, status: 'completed')
      .where('created_at > ?', 10.minutes.ago)
      .includes(:requesting_agent, :target_agent)
    
    # Build graph and detect cycles
    graph = build_collaboration_graph(recent)
    has_cycle?(graph)
  end
end
```

## UI Components

### Agent Energy Dashboard

```
┌─────────────────────────────────────────────────────────────────────────┐
│  AGENT: Data Analyst                                    Energy: 78/100  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ████████████████████████████████████████░░░░░░░░░░░░  78%              │
│                                                                          │
│  Today's Activity:                                                       │
│  ├─ Tasks completed: 12 (+45 energy)                                    │
│  ├─ Help given: 3 (+18 energy)                                          │
│  ├─ Help received: 2 (-10 energy)                                       │
│  └─ Regenerated: +5 energy                                              │
│                                                                          │
│  Capabilities:                          Collaboration Stats:            │
│  • Data Analysis: ████████░░ 85%        • Help requests made: 24        │
│  • Visualization: ███████░░░ 72%        • Help requests received: 18    │
│  • SQL Queries:   ████████░░ 82%        • Avg helpfulness rating: 4.2   │
│  • Python:        ██████░░░░ 65%        • Independence score: 72        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Collaboration Network View

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    AGENT COLLABORATION NETWORK                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                        ┌─────────────┐                                  │
│                   ┌───►│   Scout     │◄───┐                             │
│                   │    │  (Energy:85)│    │                             │
│                   │    └──────┬──────┘    │                             │
│                   │           │           │                             │
│            advice │    delegate│    review│                             │
│                   │           ▼           │                             │
│         ┌─────────┴───┐ ┌───────────┐ ┌───┴─────────┐                   │
│         │Data Analyst │ │Tool Builder│ │ Researcher │                   │
│         │ (Energy:78) │ │ (Energy:62)│ │ (Energy:91)│                   │
│         └─────────────┘ └───────────┘ └─────────────┘                   │
│                   │           │           │                             │
│                   └───────────┼───────────┘                             │
│                               ▼                                         │
│                    ┌───────────────────┐                                │
│                    │ Integration Agent │                                │
│                    │   (Energy: 45)    │                                │
│                    └───────────────────┘                                │
│                                                                          │
│  Legend: ──► advice  ═══► delegation  - - -> subtask                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Energy System
- [ ] Create `AgentEnergyState` model and migrations
- [ ] Implement energy earning/spending logic
- [ ] Add energy regeneration background job
- [ ] Create energy dashboard UI
- [ ] Integrate with existing agent execution

### Phase 2: Collaboration Protocol
- [ ] Create `AgentCollaborationRequest` model
- [ ] Implement `AgentCollaborationService`
- [ ] Add collaboration tools to agents
- [ ] Build collaboration request UI
- [ ] Add limits and circuit breakers

### Phase 3: Capability Profiles
- [ ] Create `AgentCapabilityProfile` model
- [ ] Implement capability learning from outcomes
- [ ] Add tool proficiency tracking
- [ ] Build capability visualization UI

### Phase 4: RL Task Router
- [ ] Implement `TaskRouter` with basic policy
- [ ] Add Q-learning or bandit algorithm
- [ ] Create routing decision logging
- [ ] Build A/B testing framework
- [ ] Add policy update pipeline

### Phase 5: Advanced Features
- [ ] Multi-agent collaboration (3+ agents)
- [ ] Collaboration templates for common patterns
- [ ] Agent mentorship system
- [ ] Cross-entity collaboration (marketplace)

## Metrics & Monitoring

### Key Metrics to Track

1. **Energy Economy**
   - Total energy in circulation
   - Energy velocity (earned/spent per hour)
   - Energy distribution across agents

2. **Collaboration Efficiency**
   - Help request success rate
   - Average time to get help
   - Collaboration ROI (value gained vs energy spent)

3. **Agent Performance**
   - Solo success rate vs collaborative success rate
   - Capability growth over time
   - Task completion quality trends

4. **System Health**
   - Collaboration depth distribution
   - Circuit breaker trips
   - Queue wait times

## Open Questions

1. **Energy Economy Balance**: How do we prevent energy inflation/deflation?
2. **Cold Start**: How do new agents get initial energy and capabilities?
3. **Fairness**: How do we ensure all agents get opportunities to help?
4. **Gaming**: How do we prevent agents from gaming the energy system?
5. **Human Override**: When should users be able to force collaboration?

## Related Documentation

- [Agent Factory](./AGENT_FACTORY.md) - Creating agents
- [Tool Factory](./TOOL_FACTORY.md) - Creating tools
- [Code Runner](./CODE_RUNNER_ARCHITECTURE.md) - Code execution system

