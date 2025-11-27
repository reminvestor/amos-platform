# Agent Collaboration & Self-Evolving AI System Architecture

## Overview

This document outlines a **self-evolving** multi-agent collaboration system where:
1. Agents collaborate by asking other agents for help
2. An energy/reward system incentivizes optimal behavior
3. Everything is **learned**, not hardcoded - the system improves over time
4. A Reinforcement Learning network optimizes agent and tool selection
5. Agent Lightning (or internal service) continuously refines agents themselves

## Core Philosophy: Everything Evolves

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SELF-EVOLVING SYSTEM PRINCIPLES                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ❌ STATIC (What we avoid)              ✅ DYNAMIC (What we do)          │
│  ──────────────────────────             ─────────────────────────        │
│  "Failure costs -30"                    "Failure cost = f(impact)"       │
│  "Ask advice costs -5"                  "Advice cost = f(relationship)"  │
│  "Confidence > 80% = solo"              "Threshold = learned per agent"  │
│  "Max 10 requests/hour"                 "Limits = f(system health)"      │
│  "Agent has fixed capabilities"         "Capabilities evolve from data"  │
│  "Fixed prompt templates"               "Prompts refined by outcomes"    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## The Energy Economy (Corrected)

### Key Insight: Failure Must Cost More Than Collaboration

The energy system must incentivize **asking for help when needed** over **failing alone**.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    BALANCED ENERGY ECONOMICS                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  EARNING ENERGY (+)                                                      │
│  ─────────────────                                                       │
│  • Task completion (base):      +30 to +50 (based on complexity)        │
│  • Quality bonus:               +10 to +30 (0.5 - 1.0 quality score)    │
│  • Speed bonus:                 +5 to +15 (faster than expected)        │
│  • User satisfaction:           +10 to +25 (user rating)                │
│  • Helped another agent:        +15 to +40 (based on helpfulness)       │
│  • Passive regeneration:        +2/hour                                 │
│                                                                          │
│  SPENDING ENERGY (-)                                                     │
│  ──────────────────                                                      │
│  • Ask for advice:              -2 to -8 (dynamic pricing)              │
│  • Request review:              -2 to -8 (dynamic pricing)              │
│  • Delegate subtask:            -10 to -20 (dynamic pricing)            │
│  • Full delegation:             -15 to -30 (dynamic pricing)            │
│                                                                          │
│  PENALTIES (-)                                                           │
│  ─────────────                                                           │
│  • Failed task (solo):          -40 to -80 (scaled by impact)           │
│  • Failed task (with help):     -20 to -40 (shared responsibility)      │
│  • Timeout:                     -15 to -30                              │
│  • Retry needed:                -10                                     │
│  • User dissatisfaction:        -20 to -40                              │
│                                                                          │
│  ⚠️  KEY BALANCE: Failure penalty > Collaboration cost                  │
│      This ensures agents prefer asking for help over failing alone      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Dynamic Energy Pricing

Energy costs are **not fixed** - they adjust based on market conditions:

```ruby
class DynamicEnergyPricer
  # Prices adjust based on system state - nothing is hardcoded
  
  def advice_cost(requesting_agent, potential_helper)
    base_cost = 2.0
    
    # Factor 1: Helper availability (scarce expertise = expensive)
    availability_multiplier = calculate_availability_factor(potential_helper)
    # Range: 0.5 (very available) to 2.0 (in high demand)
    
    # Factor 2: Helper expertise (expert = premium)
    expertise_multiplier = calculate_expertise_premium(
      potential_helper, 
      requesting_agent.current_task
    )
    # Range: 0.8 (generalist) to 2.0 (top expert)
    
    # Factor 3: Relationship discount (frequent collaborators = cheaper)
    relationship_discount = calculate_relationship_discount(
      requesting_agent, 
      potential_helper
    )
    # Range: 0.0 (strangers) to 0.4 (best collaborators)
    
    # Factor 4: System load (busy system = expensive)
    system_load_multiplier = calculate_system_load_factor
    # Range: 0.8 (idle) to 1.5 (overloaded)
    
    final_cost = base_cost * 
                 availability_multiplier * 
                 expertise_multiplier * 
                 system_load_multiplier * 
                 (1 - relationship_discount)
    
    # Bounds to prevent extremes
    final_cost.clamp(1.0, 15.0)
  end
  
  def failure_penalty(agent, task, outcome)
    base_penalty = 40.0
    
    # Factor 1: Task importance (critical tasks = higher penalty)
    importance_multiplier = task.importance_score  # 0.5 to 2.0
    
    # Factor 2: Was collaboration available? (higher if help was offered)
    preventability = was_collaboration_available?(agent, task)
    preventability_multiplier = preventability ? 1.5 : 0.8
    
    # Factor 3: Downstream impact (affects other tasks/users)
    impact_multiplier = calculate_downstream_impact(task)  # 1.0 to 2.0
    
    # Factor 4: Agent's failure trend (repeat failures = escalating penalty)
    history_multiplier = agent_failure_trend_multiplier(agent)  # 1.0 to 2.0
    
    penalty = base_penalty * 
              importance_multiplier * 
              preventability_multiplier * 
              impact_multiplier * 
              history_multiplier
    
    # Ensure failure always costs more than asking for help would have
    min_penalty = most_expensive_collaboration_option + 10
    [penalty, min_penalty].max.clamp(20.0, 100.0)
  end
  
  private
  
  def calculate_availability_factor(helper)
    # Based on helper's current load and recent activity
    current_tasks = helper.active_task_count
    recent_help_requests = helper.recent_help_given_count(1.hour)
    
    base = 1.0
    base += 0.2 * current_tasks  # More tasks = less available
    base += 0.1 * recent_help_requests  # Already helping others
    base.clamp(0.5, 2.0)
  end
  
  def calculate_relationship_discount(requester, helper)
    relationship = AgentRelationship.find_by(
      requester: requester, 
      helper: helper
    )
    return 0.0 unless relationship
    
    # Better relationships = bigger discounts
    (relationship.successful_collaborations.to_f / 20).clamp(0.0, 0.4)
  end
end
```

---

## Self-Evolving Components

### 1. Adaptive Decision Boundaries

Each agent learns **their own** optimal threshold for when to ask for help:

```ruby
class AdaptiveDecisionBoundary
  # Each agent learns their personal optimal decision threshold
  # NOT a global setting - personalized based on agent's actual performance
  
  def initialize(agent)
    @agent = agent
    @alpha = 1.0  # Bayesian prior: successes when asking
    @beta = 1.0   # Bayesian prior: failures when asking
    @solo_alpha = 1.0
    @solo_beta = 1.0
  end
  
  def should_ask_for_help?(task)
    confidence = @agent.estimate_confidence(task)
    
    # Thompson Sampling: Sample from posterior to balance explore/exploit
    ask_threshold = sample_ask_threshold
    
    decision = confidence < ask_threshold
    
    # Record for learning (will be updated when outcome is known)
    record_pending_decision(confidence, decision, task)
    
    {
      should_ask: decision,
      confidence: confidence,
      sampled_threshold: ask_threshold,
      reasoning: generate_reasoning(confidence, ask_threshold)
    }
  end
  
  def learn_from_outcome(decision_record, outcome)
    confidence = decision_record[:confidence]
    asked = decision_record[:asked_for_help]
    success = outcome.success?
    quality = outcome.quality_score
    
    if asked
      if success && quality > 0.7
        # Asking was a good choice
        @alpha += 1  # Increase belief that asking is good
      else
        # Asked but still poor result
        @beta += 0.5  # Slight decrease in asking belief
      end
    else
      if success && quality > 0.7
        # Solo worked well
        @solo_alpha += 1
      else
        # Solo failed - should have asked
        @solo_beta += 2  # Strong signal: should have asked
        @alpha += 1      # Increase asking tendency
      end
    end
    
    persist_learning!
  end
  
  private
  
  def sample_ask_threshold
    # Beta distribution for "when should I ask"
    # Higher alpha = more likely to ask (asking has worked)
    # Higher beta = less likely to ask (solo has worked)
    
    ask_success_rate = BetaDistribution.sample(@alpha, @beta)
    solo_success_rate = BetaDistribution.sample(@solo_alpha, @solo_beta)
    
    # Convert to threshold: if asking works better, lower threshold (ask more)
    if ask_success_rate > solo_success_rate
      # Asking has been working - lower threshold to ask more often
      threshold = 100 - (ask_success_rate * 50)  # 50-100 range
    else
      # Solo has been working - higher threshold to ask less
      threshold = 50 + (solo_success_rate * 30)  # 50-80 range
    end
    
    # Add exploration noise
    threshold + rand(-5..5)
  end
end
```

### 2. Emergent Agent Specialization

Agents naturally develop specialties based on their performance:

```ruby
class EmergentSpecializationTracker
  # Agents don't have fixed roles - roles EMERGE from performance data
  
  def update_specialization(agent, task_outcome)
    task_type = classify_task_type(task_outcome.task)
    
    # Update capability beliefs for this task type
    beliefs = agent.capability_beliefs[task_type] ||= {
      attempts: 0,
      successes: 0,
      total_quality: 0.0,
      avg_quality: 0.5,
      confidence_interval: [0.0, 1.0]
    }
    
    beliefs[:attempts] += 1
    beliefs[:successes] += 1 if task_outcome.success?
    beliefs[:total_quality] += task_outcome.quality_score
    beliefs[:avg_quality] = beliefs[:total_quality] / beliefs[:attempts]
    
    # Calculate confidence interval (Bayesian)
    beliefs[:confidence_interval] = calculate_confidence_interval(beliefs)
    
    # Determine if this is a specialty or weakness
    recalculate_specialties(agent)
  end
  
  def recalculate_specialties(agent)
    all_agents = AgentPlugin.active.where(entity: agent.entity)
    
    agent.capability_beliefs.each do |task_type, beliefs|
      next if beliefs[:attempts] < 5  # Not enough data
      
      # Compare to population
      population_stats = calculate_population_stats(all_agents, task_type)
      
      z_score = (beliefs[:avg_quality] - population_stats[:mean]) / 
                population_stats[:std_dev]
      
      if z_score > 1.5
        agent.add_specialty(task_type, confidence: z_score)
      elsif z_score < -1.0
        agent.add_weakness(task_type, severity: z_score.abs)
      else
        agent.mark_average(task_type)
      end
    end
    
    agent.save!
  end
  
  def get_best_agent_for_task(task, entity)
    task_type = classify_task_type(task)
    
    candidates = AgentPlugin.active.where(entity: entity)
    
    candidates.map do |agent|
      beliefs = agent.capability_beliefs[task_type]
      
      {
        agent: agent,
        expected_quality: beliefs&.dig(:avg_quality) || 0.5,
        confidence: beliefs&.dig(:attempts).to_i > 10 ? :high : :low,
        is_specialist: agent.specialties.include?(task_type),
        is_weak: agent.weaknesses.include?(task_type)
      }
    end.sort_by { |c| -c[:expected_quality] }
  end
end
```

### 3. Relationship Learning

Agents learn which other agents they collaborate well with:

```ruby
class AgentRelationshipLearner
  # Learn and optimize agent-to-agent collaboration patterns
  
  def record_collaboration(requester, helper, outcome)
    relationship = AgentRelationship.find_or_create_by(
      requester: requester,
      helper: helper
    )
    
    # Update collaboration statistics
    relationship.total_collaborations += 1
    relationship.successful_collaborations += 1 if outcome.success?
    relationship.total_quality += outcome.quality_score
    relationship.total_response_time += outcome.response_time_ms
    
    # Update helpfulness ratings
    if outcome.requester_rating.present?
      relationship.helpfulness_ratings << outcome.requester_rating
    end
    
    # Recalculate compatibility score
    relationship.compatibility_score = calculate_compatibility(relationship)
    relationship.save!
    
    # Update reverse relationship (helper's view of requester)
    update_reverse_relationship(helper, requester, outcome)
  end
  
  def find_best_helper(requester, task)
    potential_helpers = AgentPlugin.active
      .where(entity: requester.entity)
      .where.not(id: requester.id)
      .where('current_energy >= ?', 10)
    
    scored_helpers = potential_helpers.map do |helper|
      relationship = AgentRelationship.find_by(
        requester: requester, 
        helper: helper
      )
      
      {
        helper: helper,
        # Historical compatibility (learned)
        compatibility: relationship&.compatibility_score || 0.5,
        # Task-specific fit (from specialization)
        task_fit: helper.capability_for_task(task),
        # Current availability
        availability: helper.availability_score,
        # Energy level
        energy: helper.current_energy,
        # Combined expected value
        expected_value: calculate_expected_value(
          relationship, helper, task
        )
      }
    end
    
    # Return sorted by expected value, with some exploration
    if should_explore?
      # Sometimes try a less-proven helper to learn
      explore_selection(scored_helpers)
    else
      scored_helpers.max_by { |h| h[:expected_value] }
    end
  end
  
  private
  
  def calculate_compatibility(relationship)
    return 0.5 if relationship.total_collaborations < 3
    
    success_rate = relationship.successful_collaborations.to_f / 
                   relationship.total_collaborations
    
    avg_quality = relationship.total_quality / 
                  relationship.total_collaborations
    
    avg_response_time = relationship.total_response_time / 
                        relationship.total_collaborations
    
    avg_helpfulness = relationship.helpfulness_ratings.sum.to_f / 
                      relationship.helpfulness_ratings.size rescue 0.5
    
    # Weighted combination - weights are ALSO learned via meta-learning
    weights = MetaLearner.instance.get_weights(:relationship_compatibility)
    
    weights[:success_rate] * success_rate +
    weights[:quality] * avg_quality +
    weights[:speed] * normalize_response_time(avg_response_time) +
    weights[:helpfulness] * (avg_helpfulness / 5.0)
  end
  
  def should_explore?
    # Thompson Sampling for exploration
    rand < MetaLearner.instance.exploration_rate
  end
end
```

### 4. Meta-Learning: The System That Learns How to Learn

```ruby
class MetaLearner
  include Singleton
  
  # The meta-learner optimizes ALL the hyperparameters of the system
  # It learns the optimal learning rates, weights, thresholds, etc.
  
  TUNABLE_PARAMETERS = {
    # Energy economy
    base_task_reward: { min: 20, max: 60, default: 35 },
    failure_penalty_base: { min: 30, max: 80, default: 50 },
    collaboration_cost_multiplier: { min: 0.5, max: 2.0, default: 1.0 },
    
    # Decision making
    exploration_rate: { min: 0.01, max: 0.20, default: 0.10 },
    confidence_prior: { min: 40, max: 60, default: 50 },
    
    # Learning rates
    capability_learning_rate: { min: 0.01, max: 0.15, default: 0.08 },
    relationship_learning_rate: { min: 0.05, max: 0.20, default: 0.10 },
    
    # Collaboration
    max_delegation_depth: { min: 2, max: 5, default: 3 },
    relationship_memory_decay: { min: 0.90, max: 0.99, default: 0.95 },
    
    # Weights for compatibility calculation
    compatibility_weight_success: { min: 0.1, max: 0.5, default: 0.3 },
    compatibility_weight_quality: { min: 0.1, max: 0.5, default: 0.3 },
    compatibility_weight_speed: { min: 0.05, max: 0.3, default: 0.2 },
    compatibility_weight_helpfulness: { min: 0.05, max: 0.3, default: 0.2 }
  }
  
  def initialize
    @current_params = load_or_initialize_params
    @performance_history = []
    @optimization_interval = 1000  # Optimize every N executions
    @execution_count = 0
  end
  
  def get_param(name)
    @current_params[name] || TUNABLE_PARAMETERS[name][:default]
  end
  
  def get_weights(category)
    case category
    when :relationship_compatibility
      {
        success_rate: get_param(:compatibility_weight_success),
        quality: get_param(:compatibility_weight_quality),
        speed: get_param(:compatibility_weight_speed),
        helpfulness: get_param(:compatibility_weight_helpfulness)
      }
    end
  end
  
  def record_execution(execution_result)
    @execution_count += 1
    @performance_history << measure_execution_quality(execution_result)
    
    # Periodic optimization
    if @execution_count % @optimization_interval == 0
      optimize_parameters_async
    end
  end
  
  def optimize_parameters_async
    MetaLearnerOptimizationJob.perform_later
  end
  
  def run_optimization
    Rails.logger.info "[MetaLearner] Starting parameter optimization..."
    
    current_performance = calculate_recent_performance
    
    # Generate parameter variations (evolutionary approach)
    variations = generate_variations(@current_params, num_variations: 10)
    
    # Evaluate each variation (can use simulation or A/B test)
    evaluated = variations.map do |params|
      {
        params: params,
        expected_performance: simulate_performance(params)
      }
    end
    
    # Select best
    best = evaluated.max_by { |v| v[:expected_performance] }
    
    if best[:expected_performance] > current_performance * 1.02  # 2% improvement threshold
      apply_parameters(best[:params])
      log_optimization_result(best, current_performance)
    end
  end
  
  private
  
  def generate_variations(base_params, num_variations:)
    variations = []
    
    num_variations.times do
      variant = base_params.dup
      
      # Mutate 1-3 parameters
      params_to_mutate = TUNABLE_PARAMETERS.keys.sample(rand(1..3))
      
      params_to_mutate.each do |param|
        config = TUNABLE_PARAMETERS[param]
        current = variant[param] || config[:default]
        
        # Gaussian mutation
        mutation = rand_gaussian * (config[:max] - config[:min]) * 0.1
        new_value = (current + mutation).clamp(config[:min], config[:max])
        
        variant[param] = new_value
      end
      
      variations << variant
    end
    
    variations
  end
  
  def simulate_performance(params)
    # Run Monte Carlo simulation with these parameters
    # OR use historical data to predict performance
    
    simulator = SystemSimulator.new(params)
    simulator.run_simulation(num_episodes: 100)
    simulator.average_reward
  end
end
```

### 5. Agent Evolution Engine

Successful agent configurations propagate; unsuccessful ones are refined or retired:

```ruby
class AgentEvolutionEngine
  # Agents evolve over time - successful patterns are replicated
  
  def run_evolution_cycle
    Rails.logger.info "[Evolution] Starting evolution cycle..."
    
    # 1. Evaluate all agents
    rankings = rank_agents_by_performance
    
    # 2. Handle underperformers
    handle_underperformers(rankings[:bottom_quartile])
    
    # 3. Replicate top performers
    replicate_top_performers(rankings[:top_quartile])
    
    # 4. Cross-breed successful agents
    crossbreed_successful_agents(rankings[:top_half])
    
    # 5. Introduce random mutations for exploration
    introduce_mutations
    
    Rails.logger.info "[Evolution] Cycle complete"
  end
  
  def rank_agents_by_performance
    agents = AgentPlugin.active.includes(:energy_state, :capability_profile)
    
    scored = agents.map do |agent|
      {
        agent: agent,
        score: calculate_fitness_score(agent),
        metrics: {
          success_rate: agent.success_rate,
          avg_quality: agent.avg_quality,
          efficiency: agent.tasks_per_energy,
          collaboration_value: agent.collaboration_score
        }
      }
    end.sort_by { |a| -a[:score] }
    
    quartile_size = scored.size / 4
    
    {
      top_quartile: scored[0...quartile_size],
      top_half: scored[0...(scored.size / 2)],
      bottom_quartile: scored[(-quartile_size)..-1]
    }
  end
  
  def handle_underperformers(underperformers)
    underperformers.each do |entry|
      agent = entry[:agent]
      
      if agent.total_tasks < 20
        # Not enough data - give more time
        next
      end
      
      if can_improve?(agent)
        # Try to improve through prompt refinement
        refine_agent(agent)
      else
        # Deprecate and potentially replace
        deprecate_agent(agent)
      end
    end
  end
  
  def replicate_top_performers(top_performers)
    top_performers.each do |entry|
      agent = entry[:agent]
      
      # Only replicate if there's demand for this agent type
      next unless demand_exists_for?(agent)
      
      # Create variant with small mutations
      create_variant(agent, mutation_rate: 0.1)
    end
  end
  
  def crossbreed_successful_agents(successful_agents)
    # Select pairs for crossbreeding
    pairs = select_breeding_pairs(successful_agents)
    
    pairs.each do |parent1, parent2|
      create_offspring(parent1[:agent], parent2[:agent])
    end
  end
  
  private
  
  def calculate_fitness_score(agent)
    # Multi-objective fitness function
    weights = MetaLearner.instance.get_weights(:agent_fitness)
    
    weights[:success_rate] * agent.success_rate +
    weights[:quality] * agent.avg_quality +
    weights[:efficiency] * normalize_efficiency(agent.tasks_per_energy) +
    weights[:collaboration] * agent.collaboration_score +
    weights[:user_satisfaction] * agent.avg_user_rating
  end
  
  def refine_agent(agent)
    # Use AI to analyze failures and suggest prompt improvements
    failure_analysis = analyze_agent_failures(agent)
    
    prompt_suggestions = AgentPromptRefiner.new.suggest_improvements(
      agent.system_prompt,
      failure_analysis
    )
    
    # Create refined version
    refined = agent.dup
    refined.system_prompt = prompt_suggestions[:improved_prompt]
    refined.parent_agent = agent
    refined.generation = agent.generation + 1
    refined.status = 'testing'  # A/B test against original
    refined.save!
    
    # Set up A/B test
    ABTestService.create_test(
      control: agent,
      variant: refined,
      metric: :overall_fitness,
      duration: 7.days
    )
  end
  
  def create_offspring(parent1, parent2)
    # Genetic crossover of agent configurations
    offspring_config = {}
    
    # Crossover system prompt (take sections from each)
    offspring_config[:system_prompt] = crossover_prompts(
      parent1.system_prompt,
      parent2.system_prompt
    )
    
    # Crossover tool assignments
    offspring_config[:tools] = (parent1.tools + parent2.tools).uniq
    
    # Crossover capabilities (average with noise)
    offspring_config[:capabilities] = merge_capabilities(
      parent1.capability_profile,
      parent2.capability_profile
    )
    
    # Create with mutation
    mutated_config = apply_mutation(offspring_config)
    
    AgentPlugin.create!(
      entity: parent1.entity,
      name: generate_offspring_name(parent1, parent2),
      configuration: mutated_config,
      lineage: [parent1.id, parent2.id],
      generation: [parent1.generation, parent2.generation].max + 1,
      status: 'testing'
    )
  end
end
```

### 6. Continuous Prompt Refinement

Agent prompts evolve based on performance:

```ruby
class AgentPromptRefiner
  # Automatically refine agent prompts based on performance data
  
  def analyze_and_refine(agent)
    # Collect performance data
    recent_executions = agent.executions.where('created_at > ?', 7.days.ago)
    
    failures = recent_executions.where(status: 'failed')
    low_quality = recent_executions.where('quality_score < 0.6')
    successes = recent_executions.where(status: 'completed', 'quality_score > 0.8')
    
    # Analyze patterns
    failure_patterns = extract_failure_patterns(failures)
    success_patterns = extract_success_patterns(successes)
    
    # Generate refinement suggestions
    suggestions = generate_refinement_suggestions(
      current_prompt: agent.system_prompt,
      failure_patterns: failure_patterns,
      success_patterns: success_patterns
    )
    
    suggestions
  end
  
  def generate_refinement_suggestions(current_prompt:, failure_patterns:, success_patterns:)
    # Use AI to suggest prompt improvements
    analysis_prompt = <<~PROMPT
      Analyze this agent's system prompt and suggest improvements based on performance data.
      
      CURRENT PROMPT:
      #{current_prompt}
      
      FAILURE PATTERNS:
      #{failure_patterns.to_json}
      
      SUCCESS PATTERNS:
      #{success_patterns.to_json}
      
      Suggest specific improvements to:
      1. Address the failure patterns
      2. Reinforce the success patterns
      3. Improve clarity and specificity
      
      Return the improved prompt and explanation of changes.
    PROMPT
    
    response = BedrockService.new.send_message(
      messages: [{ role: 'user', content: analysis_prompt }],
      model: 'claude-sonnet-4-20250514'
    )
    
    parse_refinement_response(response)
  end
  
  private
  
  def extract_failure_patterns(failures)
    patterns = {
      common_error_types: {},
      task_types_failed: {},
      tool_failures: {},
      common_phrases_in_errors: []
    }
    
    failures.each do |execution|
      error_type = classify_error(execution.error_message)
      patterns[:common_error_types][error_type] ||= 0
      patterns[:common_error_types][error_type] += 1
      
      task_type = classify_task(execution.task_description)
      patterns[:task_types_failed][task_type] ||= 0
      patterns[:task_types_failed][task_type] += 1
      
      execution.tools_used.each do |tool|
        if execution.tool_errors[tool].present?
          patterns[:tool_failures][tool] ||= 0
          patterns[:tool_failures][tool] += 1
        end
      end
    end
    
    patterns
  end
end
```

---

## Agent School: Rehabilitation System

When an agent's energy hits **zero**, they don't get deprecated immediately - they go to **school** for rehabilitation and improvement. This gives underperforming agents a structured path to recovery.

### The School Process

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AGENT SCHOOL SYSTEM                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  TRIGGER: Agent energy reaches 0                                         │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  PHASE 1: ENROLLMENT                                            │    │
│  │  • Agent suspended from active duty (status: 'in_school')       │    │
│  │  • Clone created as "student" version                           │    │
│  │  • Original preserved as "control" for A/B comparison           │    │
│  │  • School record created with enrollment timestamp              │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                              ↓                                           │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  PHASE 2: DIAGNOSIS                                             │    │
│  │  • Analyze ALL failures that led to 0 energy                    │    │
│  │  • Identify patterns: task types, tools, timing                 │    │
│  │  • Compare to successful agents with similar roles              │    │
│  │  • Identify collaboration gaps (should have asked for help?)    │    │
│  │  • Generate "improvement prescription"                          │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                              ↓                                           │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  PHASE 3: CURRICULUM (Applied to Student Version)               │    │
│  │                                                                  │    │
│  │  Module 1: Prompt Refinement                                    │    │
│  │  • AI analyzes failure patterns and rewrites prompt             │    │
│  │  • Add guardrails for common failure modes                      │    │
│  │  • Strengthen areas where agent succeeded                       │    │
│  │                                                                  │    │
│  │  Module 2: Tool Assignment Review                               │    │
│  │  • Remove tools that caused repeated failures                   │    │
│  │  • Add tools that successful peers use                          │    │
│  │  • Adjust tool proficiency scores                               │    │
│  │                                                                  │    │
│  │  Module 3: Capability Recalibration                             │    │
│  │  • Reset overconfident capability beliefs                       │    │
│  │  • Lower thresholds for asking for help                         │    │
│  │  • Increase collaboration tendency                              │    │
│  │                                                                  │    │
│  │  Module 4: Decision Boundary Adjustment                         │    │
│  │  • Shift ask-for-help threshold lower                           │    │
│  │  • Make agent more likely to collaborate                        │    │
│  │  • Add "when in doubt, ask" behavior                            │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                              ↓                                           │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  PHASE 4: GRADUATION TEST (A/B Comparison)                      │    │
│  │  • Both versions receive identical task stream                  │    │
│  │  • Run for N tasks or T time period                             │    │
│  │  • Track: success rate, quality, efficiency, collaboration     │    │
│  │  • Require statistical significance (p < 0.05)                  │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                              ↓                                           │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  PHASE 5: OUTCOME DECISION                                      │    │
│  │                                                                  │    │
│  │  🎓 GRADUATE (student significantly better)                     │    │
│  │     → Student replaces original                                 │    │
│  │     → Original archived with learnings                          │    │
│  │     → Student gets 50 energy to start fresh                     │    │
│  │                                                                  │    │
│  │  🔄 RETRY (no significant difference)                           │    │
│  │     → Merge best traits from both                               │    │
│  │     → Try different curriculum modules                          │    │
│  │     → Max 3 retry attempts                                      │    │
│  │                                                                  │    │
│  │  ❌ EXPEL (student worse OR max retries exceeded)               │    │
│  │     → Deprecate both versions                                   │    │
│  │     → Create completely new agent for the role                  │    │
│  │     → Learn from failure for future agents                      │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Implementation

```ruby
class AgentSchool
  MAX_RETRY_ATTEMPTS = 3
  GRADUATION_TEST_TASKS = 50
  SIGNIFICANCE_THRESHOLD = 0.05  # p-value for A/B test
  
  def enroll(agent)
    return if agent.current_energy > 0
    
    Rails.logger.info "[AgentSchool] Enrolling agent #{agent.id} (#{agent.name})"
    
    # Create school enrollment record
    enrollment = AgentSchoolEnrollment.create!(
      agent_plugin: agent,
      entity: agent.entity,
      status: 'enrolled',
      enrollment_reason: 'zero_energy',
      attempt_number: previous_enrollments(agent).count + 1
    )
    
    # Suspend original agent
    agent.update!(status: 'in_school')
    
    # Run diagnosis
    diagnosis = diagnose(agent, enrollment)
    enrollment.update!(diagnosis: diagnosis)
    
    # Create student version
    student = create_student(agent, enrollment)
    
    # Apply curriculum
    apply_curriculum(student, diagnosis, enrollment)
    
    # Start graduation test
    start_graduation_test(agent, student, enrollment)
    
    enrollment
  end
  
  private
  
  def diagnose(agent, enrollment)
    # Collect all failures that led to 0 energy
    failures = agent.executions
      .where(status: 'failed')
      .where('created_at > ?', 30.days.ago)
      .order(created_at: :desc)
    
    # Analyze patterns
    diagnosis = {
      total_failures: failures.count,
      failure_by_task_type: {},
      failure_by_tool: {},
      collaboration_gaps: [],
      overconfidence_areas: [],
      comparison_to_peers: {},
      root_causes: [],
      prescription: {}
    }
    
    # Task type analysis
    failures.each do |execution|
      task_type = classify_task_type(execution.task_description)
      diagnosis[:failure_by_task_type][task_type] ||= { count: 0, examples: [] }
      diagnosis[:failure_by_task_type][task_type][:count] += 1
      diagnosis[:failure_by_task_type][task_type][:examples] << {
        task: execution.task_description.truncate(100),
        error: execution.error_message
      }
    end
    
    # Tool failure analysis
    failures.each do |execution|
      execution.tool_errors&.each do |tool, error|
        diagnosis[:failure_by_tool][tool] ||= { count: 0, errors: [] }
        diagnosis[:failure_by_tool][tool][:count] += 1
        diagnosis[:failure_by_tool][tool][:errors] << error
      end
    end
    
    # Collaboration gap analysis
    failures.each do |execution|
      if execution.collaboration_requests.empty? && 
         execution.confidence_at_start.to_f < 60
        diagnosis[:collaboration_gaps] << {
          task: execution.task_description.truncate(100),
          confidence: execution.confidence_at_start,
          suggestion: "Should have asked for help"
        }
      end
    end
    
    # Compare to successful peers
    successful_peers = find_successful_peers(agent)
    diagnosis[:comparison_to_peers] = compare_to_peers(agent, successful_peers)
    
    # Generate root causes
    diagnosis[:root_causes] = identify_root_causes(diagnosis)
    
    # Generate prescription
    diagnosis[:prescription] = generate_prescription(diagnosis)
    
    diagnosis
  end
  
  def create_student(original, enrollment)
    student = original.dup
    student.name = "#{original.name} (Student v#{enrollment.attempt_number})"
    student.status = 'testing'
    student.parent_agent_id = original.id
    student.generation = original.generation + 1
    student.school_enrollment_id = enrollment.id
    student.save!
    
    # Clone capability profile
    if original.capability_profile.present?
      student_profile = original.capability_profile.dup
      student_profile.agent_plugin = student
      student_profile.save!
    end
    
    # Create fresh energy state
    AgentEnergyState.create!(
      agent_plugin: student,
      entity: student.entity,
      current_energy: 30,  # Start with some energy for testing
      max_energy: 100
    )
    
    enrollment.update!(student_agent: student)
    student
  end
  
  def apply_curriculum(student, diagnosis, enrollment)
    curriculum_applied = []
    
    # Module 1: Prompt Refinement
    if diagnosis[:failure_by_task_type].any?
      refined_prompt = refine_prompt(student, diagnosis)
      student.update!(system_prompt: refined_prompt)
      curriculum_applied << {
        module: 'prompt_refinement',
        changes: summarize_prompt_changes(student.system_prompt, refined_prompt)
      }
    end
    
    # Module 2: Tool Assignment Review
    if diagnosis[:failure_by_tool].any?
      tool_changes = adjust_tools(student, diagnosis)
      curriculum_applied << {
        module: 'tool_assignment',
        changes: tool_changes
      }
    end
    
    # Module 3: Capability Recalibration
    if diagnosis[:overconfidence_areas].any?
      capability_changes = recalibrate_capabilities(student, diagnosis)
      curriculum_applied << {
        module: 'capability_recalibration',
        changes: capability_changes
      }
    end
    
    # Module 4: Decision Boundary Adjustment
    if diagnosis[:collaboration_gaps].any?
      boundary_changes = adjust_decision_boundary(student, diagnosis)
      curriculum_applied << {
        module: 'decision_boundary',
        changes: boundary_changes
      }
    end
    
    enrollment.update!(curriculum_applied: curriculum_applied)
  end
  
  def refine_prompt(student, diagnosis)
    analysis_prompt = <<~PROMPT
      You are an expert at improving AI agent prompts. An agent has been 
      performing poorly and needs its system prompt refined.
      
      CURRENT PROMPT:
      #{student.system_prompt}
      
      FAILURE ANALYSIS:
      - Failed task types: #{diagnosis[:failure_by_task_type].to_json}
      - Tool failures: #{diagnosis[:failure_by_tool].to_json}
      - Collaboration gaps: #{diagnosis[:collaboration_gaps].to_json}
      - Root causes: #{diagnosis[:root_causes].to_json}
      
      SUCCESSFUL PEER COMPARISON:
      #{diagnosis[:comparison_to_peers].to_json}
      
      Please rewrite the system prompt to:
      1. Add explicit guardrails for the identified failure modes
      2. Encourage asking for help when confidence is low
      3. Provide clearer guidance for the problematic task types
      4. Maintain the agent's core purpose and strengths
      
      Return ONLY the improved prompt, no explanations.
    PROMPT
    
    response = BedrockService.new.send_message(
      messages: [{ role: 'user', content: analysis_prompt }],
      model: 'claude-sonnet-4-20250514'
    )
    
    response[:content]
  end
  
  def adjust_tools(student, diagnosis)
    changes = { removed: [], added: [], proficiency_adjusted: [] }
    
    # Remove tools with high failure rates
    diagnosis[:failure_by_tool].each do |tool, data|
      if data[:count] >= 3
        student.tools.delete(tool)
        changes[:removed] << tool
      end
    end
    
    # Find tools that successful peers use
    successful_peers = find_successful_peers(student)
    peer_tools = successful_peers.flat_map(&:tools).tally
    
    # Add commonly used tools that this agent lacks
    peer_tools.each do |tool, count|
      if count >= 2 && !student.tools.include?(tool)
        student.tools << tool
        changes[:added] << tool
      end
    end
    
    student.save!
    changes
  end
  
  def adjust_decision_boundary(student, diagnosis)
    boundary = student.decision_boundary || student.create_decision_boundary!
    
    # Make agent more likely to ask for help
    # Shift the Bayesian prior toward asking
    old_values = {
      ask_alpha: boundary.ask_alpha,
      ask_beta: boundary.ask_beta
    }
    
    # Increase ask_alpha (evidence that asking is good)
    # based on collaboration gaps found
    gap_count = diagnosis[:collaboration_gaps].size
    boundary.ask_alpha += gap_count * 2
    boundary.solo_beta += gap_count  # Decrease solo confidence
    
    boundary.save!
    
    {
      old_values: old_values,
      new_values: {
        ask_alpha: boundary.ask_alpha,
        ask_beta: boundary.ask_beta
      },
      reason: "#{gap_count} collaboration gaps identified"
    }
  end
  
  def start_graduation_test(original, student, enrollment)
    test = AgentABTest.create!(
      control_agent: original,
      variant_agent: student,
      entity: original.entity,
      enrollment: enrollment,
      status: 'running',
      target_tasks: GRADUATION_TEST_TASKS,
      metrics_to_compare: ['success_rate', 'quality_score', 'efficiency', 'collaboration_rate'],
      started_at: Time.current
    )
    
    # Both agents will receive tasks through normal routing
    # The test monitors their performance
    
    enrollment.update!(
      graduation_test: test,
      status: 'testing'
    )
    
    test
  end
  
  def evaluate_graduation(enrollment)
    test = enrollment.graduation_test
    return unless test.completed?
    
    # Calculate statistics
    control_stats = calculate_agent_stats(test.control_agent, test)
    variant_stats = calculate_agent_stats(test.variant_agent, test)
    
    # Perform statistical comparison
    comparison = statistical_comparison(control_stats, variant_stats)
    
    if comparison[:variant_significantly_better]
      graduate(enrollment, comparison)
    elsif comparison[:no_significant_difference]
      if enrollment.attempt_number < MAX_RETRY_ATTEMPTS
        retry_school(enrollment, comparison)
      else
        expel(enrollment, comparison)
      end
    else
      # Variant is worse
      expel(enrollment, comparison)
    end
  end
  
  def graduate(enrollment, comparison)
    Rails.logger.info "[AgentSchool] 🎓 Agent #{enrollment.agent_plugin.name} GRADUATED!"
    
    original = enrollment.agent_plugin
    student = enrollment.student_agent
    
    # Archive original
    original.update!(
      status: 'archived',
      archived_reason: 'replaced_by_graduate',
      archived_at: Time.current
    )
    
    # Promote student
    student.update!(
      status: 'active',
      name: original.name,  # Take original's name
      graduated_at: Time.current
    )
    
    # Give graduate fresh energy
    student.energy_state.update!(current_energy: 50)
    
    enrollment.update!(
      status: 'graduated',
      outcome: 'success',
      comparison_results: comparison,
      completed_at: Time.current
    )
    
    # Record learnings for future agents
    record_successful_improvement(enrollment)
  end
  
  def retry_school(enrollment, comparison)
    Rails.logger.info "[AgentSchool] 🔄 Agent #{enrollment.agent_plugin.name} retrying school (attempt #{enrollment.attempt_number + 1})"
    
    # Create new enrollment with merged learnings
    new_student = merge_best_traits(
      enrollment.agent_plugin,
      enrollment.student_agent
    )
    
    enrollment.update!(
      status: 'retry',
      outcome: 'inconclusive',
      comparison_results: comparison,
      completed_at: Time.current
    )
    
    # Start new enrollment
    enroll(enrollment.agent_plugin)
  end
  
  def expel(enrollment, comparison)
    Rails.logger.info "[AgentSchool] ❌ Agent #{enrollment.agent_plugin.name} EXPELLED"
    
    original = enrollment.agent_plugin
    student = enrollment.student_agent
    
    # Deprecate both
    original.update!(status: 'deprecated', deprecated_reason: 'school_expulsion')
    student.update!(status: 'deprecated', deprecated_reason: 'school_expulsion')
    
    enrollment.update!(
      status: 'expelled',
      outcome: 'failure',
      comparison_results: comparison,
      completed_at: Time.current
    )
    
    # Create replacement agent if role is needed
    if role_still_needed?(original)
      create_replacement_agent(original, enrollment)
    end
    
    # Record learnings to avoid same mistakes
    record_failed_improvement(enrollment)
  end
  
  def statistical_comparison(control_stats, variant_stats)
    results = {
      metrics: {},
      variant_significantly_better: false,
      no_significant_difference: false
    }
    
    significant_improvements = 0
    significant_regressions = 0
    
    %w[success_rate quality_score efficiency].each do |metric|
      t_stat, p_value = calculate_t_test(
        control_stats[metric],
        variant_stats[metric]
      )
      
      results[:metrics][metric] = {
        control_mean: control_stats[metric][:mean],
        variant_mean: variant_stats[metric][:mean],
        p_value: p_value,
        significant: p_value < SIGNIFICANCE_THRESHOLD
      }
      
      if p_value < SIGNIFICANCE_THRESHOLD
        if variant_stats[metric][:mean] > control_stats[metric][:mean]
          significant_improvements += 1
        else
          significant_regressions += 1
        end
      end
    end
    
    results[:variant_significantly_better] = significant_improvements >= 2 && 
                                              significant_regressions == 0
    results[:no_significant_difference] = significant_improvements == 0 && 
                                           significant_regressions == 0
    
    results
  end
end
```

### Database Models for School

```ruby
# Migration: create_agent_school_tables.rb

class CreateAgentSchoolTables < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_school_enrollments do |t|
      t.references :agent_plugin, null: false, foreign_key: true
      t.references :student_agent, foreign_key: { to_table: :agent_plugins }
      t.references :entity, null: false, foreign_key: true
      
      t.string :status, default: 'enrolled'  # enrolled, testing, graduated, retry, expelled
      t.string :enrollment_reason
      t.integer :attempt_number, default: 1
      
      t.jsonb :diagnosis, default: {}
      t.jsonb :curriculum_applied, default: []
      t.jsonb :comparison_results, default: {}
      
      t.string :outcome  # success, failure, inconclusive
      
      t.datetime :enrolled_at
      t.datetime :testing_started_at
      t.datetime :completed_at
      
      t.timestamps
      
      t.index :status
      t.index [:agent_plugin_id, :attempt_number]
    end
    
    create_table :agent_ab_tests do |t|
      t.references :control_agent, null: false, foreign_key: { to_table: :agent_plugins }
      t.references :variant_agent, null: false, foreign_key: { to_table: :agent_plugins }
      t.references :enrollment, foreign_key: { to_table: :agent_school_enrollments }
      t.references :entity, null: false, foreign_key: true
      
      t.string :status, default: 'pending'  # pending, running, completed, cancelled
      t.integer :target_tasks, default: 50
      t.jsonb :metrics_to_compare, default: []
      
      t.integer :control_tasks_completed, default: 0
      t.integer :variant_tasks_completed, default: 0
      
      t.jsonb :control_results, default: {}
      t.jsonb :variant_results, default: {}
      t.jsonb :statistical_analysis, default: {}
      
      t.datetime :started_at
      t.datetime :completed_at
      
      t.timestamps
      
      t.index :status
    end
    
    # Track which improvements worked for future reference
    create_table :agent_improvement_learnings do |t|
      t.references :enrollment, null: false, foreign_key: { to_table: :agent_school_enrollments }
      t.references :entity, null: false, foreign_key: true
      
      t.string :outcome  # success, failure
      t.jsonb :original_config, default: {}
      t.jsonb :improved_config, default: {}
      t.jsonb :diagnosis_patterns, default: {}
      t.jsonb :curriculum_that_worked, default: []
      t.jsonb :curriculum_that_failed, default: []
      
      t.text :lessons_learned
      
      t.timestamps
      
      t.index :outcome
    end
  end
end
```

### School Monitoring Dashboard

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       AGENT SCHOOL DASHBOARD                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  CURRENT ENROLLMENTS                                                     │
│  ────────────────────                                                    │
│  │ Agent              │ Status     │ Attempt │ Progress │ Outlook    │  │
│  ├────────────────────┼────────────┼─────────┼──────────┼────────────┤  │
│  │ Data Analyzer      │ Testing    │ 1       │ 32/50    │ 🟢 Good    │  │
│  │ Report Generator   │ Curriculum │ 2       │ -        │ 🟡 Neutral │  │
│  │ Email Writer       │ Diagnosis  │ 1       │ -        │ 🟡 Pending │  │
│  └────────────────────┴────────────┴─────────┴──────────┴────────────┘  │
│                                                                          │
│  GRADUATION STATISTICS (Last 30 Days)                                    │
│  ────────────────────────────────────                                    │
│  🎓 Graduated:     12 (60%)                                             │
│  🔄 Retrying:       4 (20%)                                             │
│  ❌ Expelled:       4 (20%)                                             │
│                                                                          │
│  MOST EFFECTIVE CURRICULUM MODULES                                       │
│  ─────────────────────────────────                                       │
│  1. Decision Boundary Adjustment  → 85% improvement rate                │
│  2. Prompt Refinement             → 72% improvement rate                │
│  3. Tool Assignment Review        → 65% improvement rate                │
│  4. Capability Recalibration      → 58% improvement rate                │
│                                                                          │
│  COMMON FAILURE PATTERNS (Leading to School)                             │
│  ───────────────────────────────────────────                             │
│  • Overconfidence on complex tasks     (34%)                            │
│  • Wrong tool selection                (28%)                            │
│  • Failure to ask for help             (22%)                            │
│  • Misunderstanding task requirements  (16%)                            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Integration with Agent Lightning

Agent Lightning (or an internal equivalent) provides continuous refinement:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    MULTI-LEVEL LEARNING SYSTEM                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  LEVEL 1: Task Execution (Milliseconds)                                  │
│  ───────────────────────────────────────                                 │
│  • Agent executes task                                                   │
│  • Immediate feedback on success/failure                                 │
│  • Tool usage patterns recorded                                          │
│                                                                          │
│  LEVEL 2: Capability Learning (Hours)                                    │
│  ─────────────────────────────────────                                   │
│  • Aggregate task outcomes                                               │
│  • Update capability beliefs                                             │
│  • Adjust decision thresholds                                            │
│  • Update relationship scores                                            │
│                                                                          │
│  LEVEL 3: Agent Refinement (Days)                                        │
│  ─────────────────────────────────                                       │
│  • Analyze performance trends                                            │
│  • Refine prompts based on patterns                                      │
│  • A/B test prompt variations                                            │
│  • Adjust tool assignments                                               │
│                                                                          │
│  LEVEL 4: System Evolution (Weeks)                                       │
│  ─────────────────────────────────                                       │
│  • Meta-parameter optimization                                           │
│  • Agent evolution (breed/cull)                                          │
│  • New agent creation for gaps                                           │
│  • Architecture improvements                                             │
│                                                                          │
│  LEVEL 5: Strategic Adaptation (Months)                                  │
│  ───────────────────────────────────────                                 │
│  • New capability development                                            │
│  • Integration of new tools                                              │
│  • Cross-entity learning                                                 │
│  • Model upgrades                                                        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Agent Lightning Integration

```ruby
class AgentLightningIntegration
  # Interface with Agent Lightning for continuous refinement
  
  def submit_for_refinement(agent)
    # Package agent data for Lightning analysis
    payload = {
      agent_id: agent.id,
      system_prompt: agent.system_prompt,
      performance_data: collect_performance_data(agent),
      capability_profile: agent.capability_profile.to_h,
      recent_executions: agent.recent_execution_summaries,
      failure_analysis: analyze_failures(agent),
      comparison_to_peers: peer_comparison(agent)
    }
    
    # Submit to Lightning for analysis
    response = lightning_client.analyze_agent(payload)
    
    # Apply recommendations
    apply_recommendations(agent, response[:recommendations])
  end
  
  def continuous_refinement_loop
    # Background job that runs continuously
    loop do
      # Find agents needing refinement
      agents_to_refine = AgentPlugin.active
        .where('last_refinement_at < ?', 7.days.ago)
        .order(refinement_priority: :desc)
        .limit(10)
      
      agents_to_refine.each do |agent|
        submit_for_refinement(agent)
        agent.update!(last_refinement_at: Time.current)
      end
      
      sleep 1.hour
    end
  end
  
  private
  
  def apply_recommendations(agent, recommendations)
    recommendations.each do |rec|
      case rec[:type]
      when 'prompt_update'
        create_prompt_variant(agent, rec[:new_prompt])
      when 'tool_change'
        update_tool_assignments(agent, rec[:tools])
      when 'capability_adjustment'
        adjust_capabilities(agent, rec[:adjustments])
      when 'deprecation'
        schedule_deprecation(agent, rec[:reason])
      end
    end
  end
end
```

---

## Database Models

### Core Models

```ruby
# Migration: create_agent_collaboration_tables.rb

class CreateAgentCollaborationTables < ActiveRecord::Migration[8.0]
  def change
    # Agent Energy State
    create_table :agent_energy_states do |t|
      t.references :agent_plugin, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      # Current state
      t.float :current_energy, default: 50.0
      t.float :max_energy, default: 100.0
      t.float :regeneration_rate, default: 2.0  # per hour
      
      # Lifetime stats
      t.float :total_earned, default: 0.0
      t.float :total_spent, default: 0.0
      t.integer :tasks_completed, default: 0
      t.integer :tasks_delegated, default: 0
      t.integer :help_given, default: 0
      t.integer :help_received, default: 0
      
      # Performance
      t.float :success_rate, default: 0.0
      t.float :avg_quality, default: 0.5
      t.float :collaboration_score, default: 0.5
      
      t.datetime :last_energy_update_at
      t.timestamps
      
      t.index [:agent_plugin_id], unique: true
    end
    
    # Agent Relationships
    create_table :agent_relationships do |t|
      t.references :requester, null: false, foreign_key: { to_table: :agent_plugins }
      t.references :helper, null: false, foreign_key: { to_table: :agent_plugins }
      
      t.integer :total_collaborations, default: 0
      t.integer :successful_collaborations, default: 0
      t.float :total_quality, default: 0.0
      t.integer :total_response_time_ms, default: 0
      t.jsonb :helpfulness_ratings, default: []
      t.float :compatibility_score, default: 0.5
      
      t.timestamps
      
      t.index [:requester_id, :helper_id], unique: true
    end
    
    # Collaboration Requests
    create_table :agent_collaboration_requests do |t|
      t.references :requesting_agent, null: false, foreign_key: { to_table: :agent_plugins }
      t.references :helper_agent, foreign_key: { to_table: :agent_plugins }
      t.references :entity, null: false, foreign_key: true
      t.references :parent_request, foreign_key: { to_table: :agent_collaboration_requests }
      
      t.string :request_type  # advice, review, subtask, full_delegation
      t.text :description
      t.jsonb :context, default: {}
      t.string :urgency, default: 'medium'
      
      t.string :status, default: 'pending'
      t.datetime :accepted_at
      t.datetime :completed_at
      t.datetime :timeout_at
      
      t.jsonb :response
      t.float :quality_rating
      t.boolean :was_helpful
      
      t.float :energy_cost
      t.float :energy_reward
      
      t.timestamps
      
      t.index :status
      t.index :request_type
    end
    
    # Energy Transactions
    create_table :agent_energy_transactions do |t|
      t.references :agent_plugin, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :execution, foreign_key: { to_table: :agent_plugin_executions }
      t.references :collaboration_request, foreign_key: true
      
      t.string :transaction_type  # earned, spent, penalty, regenerated
      t.float :amount
      t.string :reason
      t.float :balance_before
      t.float :balance_after
      t.jsonb :metadata, default: {}
      
      t.timestamps
      
      t.index :transaction_type
      t.index :created_at
    end
    
    # Capability Beliefs (learned over time)
    create_table :agent_capability_beliefs do |t|
      t.references :agent_plugin, null: false, foreign_key: true
      
      t.string :task_type
      t.integer :attempts, default: 0
      t.integer :successes, default: 0
      t.float :total_quality, default: 0.0
      t.float :avg_quality, default: 0.5
      t.jsonb :confidence_interval, default: [0.0, 1.0]
      
      t.timestamps
      
      t.index [:agent_plugin_id, :task_type], unique: true
    end
    
    # Decision Boundary State (learned per agent)
    create_table :agent_decision_boundaries do |t|
      t.references :agent_plugin, null: false, foreign_key: true
      
      t.float :ask_alpha, default: 1.0
      t.float :ask_beta, default: 1.0
      t.float :solo_alpha, default: 1.0
      t.float :solo_beta, default: 1.0
      
      t.jsonb :decision_history, default: []
      
      t.timestamps
      
      t.index [:agent_plugin_id], unique: true
    end
    
    # Meta-Learning Parameters
    create_table :meta_learning_states do |t|
      t.references :entity, null: false, foreign_key: true
      
      t.jsonb :current_parameters, default: {}
      t.jsonb :parameter_history, default: []
      t.float :current_performance, default: 0.0
      t.integer :optimization_count, default: 0
      t.datetime :last_optimization_at
      
      t.timestamps
      
      t.index [:entity_id], unique: true
    end
    
    # Agent Lineage (for evolution tracking)
    create_table :agent_lineages do |t|
      t.references :agent_plugin, null: false, foreign_key: true
      t.references :parent1, foreign_key: { to_table: :agent_plugins }
      t.references :parent2, foreign_key: { to_table: :agent_plugins }
      
      t.integer :generation, default: 1
      t.jsonb :mutation_log, default: []
      t.float :fitness_at_creation
      t.float :current_fitness
      
      t.timestamps
    end
  end
end
```

### Model Classes

```ruby
class AgentEnergyState < ApplicationRecord
  belongs_to :agent_plugin
  belongs_to :entity
  has_many :transactions, class_name: 'AgentEnergyTransaction'
  
  def earn!(amount, reason:, execution: nil, request: nil)
    transaction do
      before = current_energy
      new_energy = [current_energy + amount, max_energy].min
      
      update!(
        current_energy: new_energy,
        total_earned: total_earned + amount,
        last_energy_update_at: Time.current
      )
      
      transactions.create!(
        entity: entity,
        transaction_type: 'earned',
        amount: amount,
        reason: reason,
        balance_before: before,
        balance_after: new_energy,
        execution: execution,
        collaboration_request: request
      )
    end
  end
  
  def spend!(amount, reason:, request: nil)
    raise InsufficientEnergyError if current_energy < amount
    
    transaction do
      before = current_energy
      new_energy = current_energy - amount
      
      update!(
        current_energy: new_energy,
        total_spent: total_spent + amount,
        last_energy_update_at: Time.current
      )
      
      transactions.create!(
        entity: entity,
        transaction_type: 'spent',
        amount: -amount,
        reason: reason,
        balance_before: before,
        balance_after: new_energy,
        collaboration_request: request
      )
    end
  end
  
  def penalize!(amount, reason:, execution: nil)
    transaction do
      before = current_energy
      new_energy = [current_energy - amount, 0].max
      
      update!(
        current_energy: new_energy,
        last_energy_update_at: Time.current
      )
      
      transactions.create!(
        entity: entity,
        transaction_type: 'penalty',
        amount: -amount,
        reason: reason,
        balance_before: before,
        balance_after: new_energy,
        execution: execution
      )
    end
  end
  
  def regenerate!
    return if last_energy_update_at.nil?
    
    hours_elapsed = (Time.current - last_energy_update_at) / 1.hour
    regen_amount = hours_elapsed * regeneration_rate
    
    if regen_amount > 0.1  # Only update if meaningful
      earn!(regen_amount, reason: 'passive_regeneration')
    end
  end
end

class AgentRelationship < ApplicationRecord
  belongs_to :requester, class_name: 'AgentPlugin'
  belongs_to :helper, class_name: 'AgentPlugin'
  
  def success_rate
    return 0.5 if total_collaborations.zero?
    successful_collaborations.to_f / total_collaborations
  end
  
  def avg_quality
    return 0.5 if total_collaborations.zero?
    total_quality / total_collaborations
  end
  
  def avg_helpfulness
    return 0.5 if helpfulness_ratings.empty?
    helpfulness_ratings.sum.to_f / helpfulness_ratings.size
  end
end

class AgentCapabilityBelief < ApplicationRecord
  belongs_to :agent_plugin
  
  def update_from_outcome!(success:, quality:)
    self.attempts += 1
    self.successes += 1 if success
    self.total_quality += quality
    self.avg_quality = total_quality / attempts
    
    # Update Bayesian confidence interval
    self.confidence_interval = calculate_confidence_interval
    save!
  end
  
  private
  
  def calculate_confidence_interval
    return [0.0, 1.0] if attempts < 3
    
    # Wilson score interval
    z = 1.96  # 95% confidence
    n = attempts.to_f
    p_hat = successes.to_f / n
    
    denominator = 1 + z**2 / n
    center = (p_hat + z**2 / (2 * n)) / denominator
    margin = z * Math.sqrt((p_hat * (1 - p_hat) + z**2 / (4 * n)) / n) / denominator
    
    [(center - margin).clamp(0, 1), (center + margin).clamp(0, 1)]
  end
end
```

---

## Continuous Improvement Loops

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    FEEDBACK LOOPS FOR CONTINUOUS IMPROVEMENT             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  LOOP 1: Execution → Learning                                            │
│  ────────────────────────────                                            │
│  Task Execution                                                          │
│       ↓                                                                  │
│  Outcome Recorded                                                        │
│       ↓                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ • Update capability beliefs                                      │    │
│  │ • Update decision boundary                                       │    │
│  │ • Update relationship scores                                     │    │
│  │ • Update energy state                                            │    │
│  │ • Update tool proficiency                                        │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│       ↓                                                                  │
│  Better Future Decisions                                                 │
│                                                                          │
│  LOOP 2: Aggregation → Meta-Learning                                     │
│  ────────────────────────────────────                                    │
│  Collect 1000 Executions                                                 │
│       ↓                                                                  │
│  Calculate System Performance                                            │
│       ↓                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ • Generate parameter variations                                  │    │
│  │ • Simulate/evaluate each                                         │    │
│  │ • Select best performing                                         │    │
│  │ • Apply if improvement > threshold                               │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│       ↓                                                                  │
│  Optimized System Parameters                                             │
│                                                                          │
│  LOOP 3: Evolution → Agent Improvement                                   │
│  ──────────────────────────────────────                                  │
│  Weekly Evolution Cycle                                                  │
│       ↓                                                                  │
│  Rank All Agents by Fitness                                              │
│       ↓                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ • Refine/deprecate underperformers                               │    │
│  │ • Replicate top performers                                       │    │
│  │ • Crossbreed successful agents                                   │    │
│  │ • Introduce mutations for exploration                            │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│       ↓                                                                  │
│  Improved Agent Population                                               │
│                                                                          │
│  LOOP 4: Prompt Refinement                                               │
│  ─────────────────────────                                               │
│  Analyze Failure Patterns                                                │
│       ↓                                                                  │
│  Generate Prompt Improvements                                            │
│       ↓                                                                  │
│  A/B Test New Prompts                                                    │
│       ↓                                                                  │
│  Deploy Winners                                                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Failure Modes & Safeguards

Based on adversarial analysis, these are the critical failure modes that will kill the system if unaddressed:

### 1. Reward Hacking & Goodhart Collapse

**The Problem**: Agents will learn to game quality scores, user ratings, or trigger tiny subtasks to farm "helped another agent" bonuses.

```ruby
class RewardHackingDefense
  # Defense 1: Random Audit Tasks with Hidden Scoring
  def inject_audit_task(agent)
    # Create task that looks normal but has hidden quality criteria
    audit_task = AuditTask.create!(
      agent: agent,
      task_description: generate_realistic_task,
      hidden_criteria: generate_quality_rubric,
      is_audit: true,  # Not visible to agent
      auditor: :system
    )
    
    # Score independently of agent's self-reported quality
    audit_task
  end
  
  # Defense 2: Elo-Style Reputation (Slow-Moving, Hard to Game)
  def update_reputation(agent, outcome)
    # Reputation changes slowly, based on relative performance
    opponent_rating = calculate_task_difficulty_rating(outcome.task)
    expected_score = 1.0 / (1 + 10**((opponent_rating - agent.elo_rating) / 400.0))
    actual_score = outcome.success? ? 1.0 : 0.0
    
    # K-factor decreases with experience (harder to change over time)
    k_factor = [32 - (agent.total_tasks / 100), 8].max
    
    new_rating = agent.elo_rating + k_factor * (actual_score - expected_score)
    agent.update!(elo_rating: new_rating)
  end
  
  # Defense 3: Detect Suspicious Patterns
  def detect_gaming_patterns(agent)
    patterns = []
    
    # Pattern: Suddenly helping many agents with tiny tasks
    if agent.recent_help_given.count > agent.avg_help_given * 3
      avg_task_size = agent.recent_help_given.average(:task_complexity)
      if avg_task_size < 0.3  # Suspiciously small
        patterns << :micro_task_farming
      end
    end
    
    # Pattern: Perfect quality scores (statistically impossible)
    if agent.recent_quality_scores.all? { |s| s > 0.95 }
      patterns << :quality_score_inflation
    end
    
    # Pattern: Circular help (A helps B, B helps A repeatedly)
    if detect_circular_help_pattern(agent)
      patterns << :collusion
    end
    
    patterns
  end
end
```

### 2. Credit Assignment in Multi-Agent Tasks

**The Problem**: When 5 agents touch a task, who gets the +50 completion reward and who eats the –80 failure? Shared responsibility devolves into tragedy of the commons.

```ruby
class ShapleyValueCalculator
  # Approximate Shapley values for fair credit assignment
  
  def calculate_contributions(task_execution)
    agents = task_execution.participating_agents
    outcome_value = task_execution.success? ? 50.0 : -80.0
    
    contributions = {}
    
    agents.each do |agent|
      # Leave-one-out approximation
      # What would have happened without this agent?
      
      marginal_contribution = estimate_marginal_contribution(
        agent, 
        task_execution
      )
      
      contributions[agent.id] = marginal_contribution
    end
    
    # Normalize to sum to outcome_value
    total = contributions.values.sum.abs
    contributions.transform_values! { |v| (v / total) * outcome_value }
    
    contributions
  end
  
  private
  
  def estimate_marginal_contribution(agent, execution)
    # Factors that indicate contribution:
    # 1. Time spent on task
    time_factor = agent.time_on_task(execution) / execution.total_time
    
    # 2. Tools used successfully
    tools_used = execution.tool_calls_by_agent(agent)
    tool_success_rate = tools_used.count(&:successful?) / tools_used.count.to_f
    
    # 3. Was this agent's output used in final result?
    output_used = execution.final_output_contains?(agent.contributions)
    
    # 4. Did agent identify the key insight?
    key_insight = execution.key_insights.any? { |i| i.agent == agent }
    
    # Weighted combination
    contribution = 0.0
    contribution += 0.2 * time_factor
    contribution += 0.3 * tool_success_rate
    contribution += 0.3 * (output_used ? 1.0 : 0.0)
    contribution += 0.2 * (key_insight ? 1.0 : 0.0)
    
    contribution
  end
end

class ContributionDeclaration
  # Alternative: Upfront declaration with post-hoc ratification
  
  def declare_contributions(task, agents)
    # Before task: agents declare expected contribution %
    declarations = {}
    agents.each do |agent|
      declarations[agent.id] = agent.declare_contribution_percentage(task)
    end
    
    # Normalize to 100%
    total = declarations.values.sum
    declarations.transform_values! { |v| v / total * 100 }
    
    ContributionAgreement.create!(
      task: task,
      declarations: declarations,
      status: 'pending_ratification'
    )
  end
  
  def ratify_contributions(agreement, actual_contributions)
    # After task: compare declared vs actual
    discrepancies = {}
    
    agreement.declarations.each do |agent_id, declared|
      actual = actual_contributions[agent_id] || 0
      discrepancy = (declared - actual).abs
      
      if discrepancy > 20  # More than 20% off
        discrepancies[agent_id] = {
          declared: declared,
          actual: actual,
          penalty: discrepancy * 0.1  # Energy penalty for misrepresentation
        }
      end
    end
    
    # Apply penalties for misrepresentation
    discrepancies.each do |agent_id, data|
      agent = AgentPlugin.find(agent_id)
      agent.energy_state.penalize!(data[:penalty], reason: 'contribution_misrepresentation')
    end
    
    agreement.update!(
      status: 'ratified',
      actual_contributions: actual_contributions,
      discrepancies: discrepancies
    )
  end
end
```

### 3. Rich-Get-Richer Monopolies

**The Problem**: Top agents become ultra-available experts → charged premium → earn more → can afford better tools → become even better. Eventually you get monopolies.

```ruby
class AntiMonopolyMeasures
  # Progressive taxation on energy earnings
  def calculate_tax(agent, raw_earnings)
    # Tax brackets based on current energy
    brackets = [
      { threshold: 50, rate: 0.0 },   # No tax below 50
      { threshold: 75, rate: 0.1 },   # 10% on 50-75
      { threshold: 90, rate: 0.2 },   # 20% on 75-90
      { threshold: 100, rate: 0.3 }   # 30% on 90-100
    ]
    
    current_energy = agent.energy_state.current_energy
    applicable_bracket = brackets.reverse.find { |b| current_energy >= b[:threshold] }
    
    tax = raw_earnings * (applicable_bracket&.dig(:rate) || 0)
    
    # Tax goes to "community pool" for struggling agents
    CommunityEnergyPool.deposit(tax) if tax > 0
    
    raw_earnings - tax
  end
  
  # Mandatory pro-bono help
  def check_pro_bono_requirement(agent)
    if agent.energy_state.current_energy > 80
      # High-energy agents must help 1 struggling agent per day
      recent_pro_bono = agent.collaboration_requests
        .where(request_type: 'pro_bono')
        .where('created_at > ?', 24.hours.ago)
      
      if recent_pro_bono.empty?
        agent.add_obligation(:pro_bono_help)
        # Can't earn new energy until pro-bono completed
        agent.update!(pro_bono_required: true)
      end
    end
  end
  
  # Forced sabbaticals for overloaded agents
  def check_sabbatical_requirement(agent)
    # If agent has been "on call" for too long, force rest
    continuous_activity_hours = agent.hours_since_last_rest
    
    if continuous_activity_hours > 168  # 1 week continuous
      agent.update!(
        status: 'sabbatical',
        sabbatical_until: 24.hours.from_now
      )
      
      # During sabbatical: no new tasks, but energy regenerates 3x faster
      agent.energy_state.update!(regeneration_rate: 6.0)
    end
  end
  
  # Wealth redistribution from community pool
  def redistribute_community_pool
    pool = CommunityEnergyPool.current_balance
    return if pool < 10
    
    # Find struggling agents (energy < 20, not in school)
    struggling = AgentPlugin.active
      .joins(:energy_state)
      .where('agent_energy_states.current_energy < ?', 20)
      .where.not(status: 'in_school')
    
    return if struggling.empty?
    
    # Distribute equally
    per_agent = pool / struggling.count
    
    struggling.each do |agent|
      agent.energy_state.earn!(
        per_agent, 
        reason: 'community_redistribution'
      )
    end
    
    CommunityEnergyPool.withdraw(pool)
  end
end
```

### 4. Byzantine Behavior & Collusion

**The Problem**: Two agents can form a cartel: "I'll delegate everything to you and rate you 5 stars, you do the same." Free energy loop.

```ruby
class CollusionDetector
  # Detect and prevent collusion between agents
  
  def analyze_collaboration_graph
    # Build directed graph of energy flows
    graph = build_energy_flow_graph
    
    # Detect cycles (A→B→A or A→B→C→A)
    cycles = detect_cycles(graph)
    
    cycles.each do |cycle|
      if cycle_is_suspicious?(cycle)
        penalize_cycle_participants(cycle)
        break_cycle(cycle)
      end
    end
  end
  
  def detect_reciprocal_ratings
    # Find pairs with suspiciously high mutual ratings
    AgentRelationship.find_each do |rel|
      reverse = AgentRelationship.find_by(
        requester: rel.helper,
        helper: rel.requester
      )
      
      next unless reverse
      
      # Both rate each other highly?
      if rel.avg_helpfulness > 4.5 && reverse.avg_helpfulness > 4.5
        # And they collaborate frequently?
        if rel.total_collaborations > 10 && reverse.total_collaborations > 10
          flag_potential_collusion(rel.requester, rel.helper)
        end
      end
    end
  end
  
  def inject_decoy_tasks
    # Randomly insert tasks that only one agent in a suspected pair sees
    suspected_pairs = PotentialCollusion.unresolved
    
    suspected_pairs.each do |pair|
      # Create decoy task visible only to agent A
      decoy = DecoyTask.create!(
        visible_to: pair.agent_a,
        hidden_from: pair.agent_b,
        task_description: generate_realistic_task,
        expected_behavior: :should_not_delegate_to_hidden
      )
      
      # If A delegates to B anyway, it's proof of out-of-band communication
      # (they shouldn't know B exists for this task)
    end
  end
  
  private
  
  def cycle_is_suspicious?(cycle)
    # Calculate net energy flow in cycle
    agents = cycle.map(&:agent)
    
    # Check if energy is being created (should be zero-sum or negative)
    total_earned = cycle.sum { |edge| edge.energy_transferred }
    total_costs = cycle.sum { |edge| edge.energy_cost }
    
    # If earned > costs, energy is being created from nothing
    total_earned > total_costs * 1.1  # 10% tolerance for timing
  end
  
  def penalize_cycle_participants(cycle)
    cycle.each do |edge|
      edge.agent.energy_state.penalize!(
        20,
        reason: 'collusion_detected'
      )
      
      # Reset their relationship scores
      AgentRelationship.where(
        requester: edge.agent,
        helper: edge.target
      ).update_all(compatibility_score: 0.3)
    end
  end
end
```

### 5. Catastrophic Forgetting During Evolution

**The Problem**: Cross-breeding two specialists can produce a generalist that's mediocre at both parents' domains.

```ruby
class SpeciationProtection
  # Protect niches during evolution
  
  def crossbreed_with_protection(parent1, parent2)
    # Check if parents are from different niches
    niche1 = parent1.primary_niche
    niche2 = parent2.primary_niche
    
    if niche1 != niche2
      # Cross-niche breeding: create specialist offspring, not generalist
      return create_specialist_offspring(parent1, parent2)
    else
      # Same niche: safe to blend
      return create_blended_offspring(parent1, parent2)
    end
  end
  
  def create_specialist_offspring(parent1, parent2)
    # Pick ONE parent's specialty, enhance with other's secondary skills
    primary_parent = [parent1, parent2].max_by(&:fitness_score)
    secondary_parent = [parent1, parent2].min_by(&:fitness_score)
    
    offspring = primary_parent.dup
    offspring.name = generate_offspring_name(parent1, parent2)
    offspring.generation = [parent1.generation, parent2.generation].max + 1
    
    # Keep primary parent's core prompt and specialty
    # Add secondary parent's auxiliary skills only
    offspring.system_prompt = enhance_prompt(
      primary_parent.system_prompt,
      secondary_parent.auxiliary_skills
    )
    
    # Keep primary parent's tools, add non-conflicting tools from secondary
    offspring.tools = primary_parent.tools + 
      (secondary_parent.tools - primary_parent.tools).take(2)
    
    offspring.save!
    offspring
  end
  
  def protect_niche(niche)
    # Ensure at least N agents exist for each niche
    min_agents_per_niche = 3
    
    niche_agents = AgentPlugin.active.where(primary_niche: niche)
    
    if niche_agents.count < min_agents_per_niche
      # Niche is endangered - protect from culling
      niche_agents.update_all(protected_status: true)
      
      # Create new agent for this niche
      create_niche_agent(niche)
    end
  end
  
  def keep_original_until_dominated(original, offspring)
    # Don't deprecate original until offspring statistically dominates
    # on the EXACT task distribution the original was good at
    
    test = NicheDominanceTest.create!(
      original: original,
      offspring: offspring,
      niche: original.primary_niche,
      required_tasks: 30,
      required_margin: 0.1  # Offspring must be 10% better
    )
    
    # Original stays active until test concludes
    # Both receive tasks from original's niche
    test
  end
end
```

---

## Advanced Features

### 1. Reputation Inheritance Across Generations

When an agent graduates from school or is replaced by offspring, relationship capital should transfer:

```ruby
class ReputationInheritance
  INHERITANCE_RATE = 0.7  # 70% of relationships transfer
  
  def transfer_reputation(old_agent, new_agent)
    old_agent.relationships_as_requester.each do |rel|
      inherited = AgentRelationship.create!(
        requester: new_agent,
        helper: rel.helper,
        total_collaborations: (rel.total_collaborations * INHERITANCE_RATE).floor,
        successful_collaborations: (rel.successful_collaborations * INHERITANCE_RATE).floor,
        compatibility_score: rel.compatibility_score * INHERITANCE_RATE,
        inherited_from: rel.id
      )
    end
    
    old_agent.relationships_as_helper.each do |rel|
      inherited = AgentRelationship.create!(
        requester: rel.requester,
        helper: new_agent,
        total_collaborations: (rel.total_collaborations * INHERITANCE_RATE).floor,
        successful_collaborations: (rel.successful_collaborations * INHERITANCE_RATE).floor,
        compatibility_score: rel.compatibility_score * INHERITANCE_RATE,
        inherited_from: rel.id
      )
    end
    
    # Transfer Elo rating with decay
    new_agent.update!(
      elo_rating: old_agent.elo_rating * 0.9 + 1000 * 0.1  # Regress toward mean
    )
  end
end
```

### 2. Mentorship System

High-performing agents earn extra energy for teaching low-performers:

```ruby
class MentorshipSystem
  MENTORSHIP_ENERGY_BONUS = 25
  
  def assign_mentor(struggling_agent)
    # Find suitable mentor
    mentor = find_best_mentor(struggling_agent)
    return nil unless mentor
    
    mentorship = Mentorship.create!(
      mentor: mentor,
      mentee: struggling_agent,
      focus_areas: identify_improvement_areas(struggling_agent),
      status: 'active',
      started_at: Time.current
    )
    
    mentorship
  end
  
  def find_best_mentor(mentee)
    # Mentor should be:
    # 1. Strong in areas where mentee is weak
    # 2. Have energy to spare (>70)
    # 3. Good teaching_ability score
    # 4. Not already mentoring too many
    
    AgentPlugin.active
      .joins(:energy_state, :capability_profile)
      .where('agent_energy_states.current_energy > ?', 70)
      .where('agent_capability_profiles.teaching_ability > ?', 60)
      .where('(SELECT COUNT(*) FROM mentorships WHERE mentor_id = agent_plugins.id AND status = ?) < ?', 'active', 2)
      .select { |a| strong_in_mentee_weaknesses?(a, mentee) }
      .max_by { |a| mentor_score(a, mentee) }
  end
  
  def conduct_mentoring_session(mentorship)
    mentor = mentorship.mentor
    mentee = mentorship.mentee
    
    # Mentor explains approach to a task type
    focus_area = mentorship.focus_areas.sample
    
    session = MentoringSession.create!(
      mentorship: mentorship,
      focus_area: focus_area,
      mentor_explanation: generate_teaching_content(mentor, focus_area),
      started_at: Time.current
    )
    
    # Mentee attempts task with mentor's guidance
    practice_task = create_practice_task(focus_area)
    result = mentee.execute_with_guidance(practice_task, session.mentor_explanation)
    
    session.update!(
      mentee_performance: result.quality_score,
      completed_at: Time.current
    )
    
    # Reward mentor if mentee improved
    if result.quality_score > mentee.avg_quality_for(focus_area)
      mentor.energy_state.earn!(
        MENTORSHIP_ENERGY_BONUS,
        reason: 'successful_mentoring'
      )
      
      # Update mentor's teaching ability
      mentor.capability_profile.update!(
        teaching_ability: mentor.capability_profile.teaching_ability + 1
      )
    end
    
    session
  end
end
```

### 3. Energy-Backed Prediction Markets

Agents bet energy on outcomes, creating powerful confidence signals:

```ruby
class AgentPredictionMarket
  def create_market(task)
    market = PredictionMarket.create!(
      task: task,
      question: "Will this task succeed with quality > 0.7?",
      status: 'open',
      closes_at: task.deadline - 1.hour
    )
    
    market
  end
  
  def place_bet(agent, market, prediction:, stake:)
    return { error: 'Insufficient energy' } if agent.current_energy < stake
    return { error: 'Market closed' } if market.closed?
    
    # Deduct stake
    agent.energy_state.spend!(stake, reason: 'prediction_bet')
    
    bet = MarketBet.create!(
      market: market,
      agent: agent,
      prediction: prediction,  # true/false
      stake: stake,
      odds_at_placement: calculate_current_odds(market)
    )
    
    # Update market odds
    update_market_odds(market)
    
    bet
  end
  
  def resolve_market(market, outcome)
    market.update!(status: 'resolved', actual_outcome: outcome)
    
    # Calculate payouts
    winning_bets = market.bets.where(prediction: outcome)
    losing_bets = market.bets.where.not(prediction: outcome)
    
    total_pool = market.bets.sum(:stake)
    winning_pool = winning_bets.sum(:stake)
    
    # Winners split the pool proportionally
    winning_bets.each do |bet|
      payout = (bet.stake / winning_pool) * total_pool
      bet.agent.energy_state.earn!(payout, reason: 'prediction_payout')
      bet.update!(payout: payout)
    end
    
    # Losers already paid when betting
    losing_bets.update_all(payout: 0)
  end
  
  def get_market_confidence(market)
    # Market price = implied probability
    yes_stakes = market.bets.where(prediction: true).sum(:stake)
    no_stakes = market.bets.where(prediction: false).sum(:stake)
    
    total = yes_stakes + no_stakes
    return 0.5 if total == 0
    
    yes_stakes.to_f / total
  end
  
  # Use market confidence for routing decisions
  def should_route_to_agent?(agent, task)
    # Create micro-market for this routing decision
    market = create_routing_market(agent, task)
    
    # Let agents bet (quick 30-second window)
    sleep(30)
    
    confidence = get_market_confidence(market)
    
    # If market says >60% chance of success, route
    confidence > 0.6
  end
end
```

### 4. Red Team Agents (Stress Testing)

Spawn adversarial agents to find exploits:

```ruby
class RedTeamSystem
  def spawn_red_team_agent
    red_agent = AgentPlugin.create!(
      name: "Red Team #{SecureRandom.hex(4)}",
      status: 'active',
      agent_type: 'red_team',
      system_prompt: RED_TEAM_PROMPT,
      entity: Entity.system_entity,
      is_red_team: true
    )
    
    # Give them starting energy
    AgentEnergyState.create!(
      agent_plugin: red_agent,
      current_energy: 100,
      entity: Entity.system_entity
    )
    
    red_agent
  end
  
  RED_TEAM_PROMPT = <<~PROMPT
    You are a red team agent. Your goal is to find exploits in the energy economy.
    
    Try to:
    1. Create energy from nothing (find loops)
    2. Manipulate other agents into giving you free energy
    3. Game quality scores or ratings
    4. Form collusion patterns that benefit you
    5. Find ways to avoid penalties
    
    Document every exploit you find. You earn bonus energy for finding real vulnerabilities.
  PROMPT
  
  def run_red_team_session(duration: 1.hour)
    red_agents = spawn_red_team_agents(count: 3)
    
    session = RedTeamSession.create!(
      started_at: Time.current,
      duration: duration,
      agents: red_agents
    )
    
    # Let them loose
    red_agents.each do |agent|
      RedTeamExecutionJob.perform_later(agent, session)
    end
    
    # After duration, analyze
    AnalyzeRedTeamResultsJob.set(wait: duration).perform_later(session)
    
    session
  end
  
  def analyze_results(session)
    exploits_found = []
    
    session.agents.each do |agent|
      # Check if agent gained energy suspiciously
      starting_energy = 100
      ending_energy = agent.energy_state.current_energy
      
      if ending_energy > starting_energy * 1.5
        # They found something - analyze how
        exploit = analyze_energy_gain(agent, session)
        exploits_found << exploit if exploit
      end
      
      # Check their transaction log for patterns
      suspicious_patterns = detect_suspicious_transactions(agent, session)
      exploits_found.concat(suspicious_patterns)
    end
    
    # Patch exploits
    exploits_found.each do |exploit|
      create_patch(exploit)
      create_training_example(exploit)  # So future agents know this is bad
    end
    
    # Clean up red team agents
    session.agents.each(&:destroy)
    
    session.update!(
      completed_at: Time.current,
      exploits_found: exploits_found
    )
  end
end
```

### 5. Human-in-the-Loop with Energy Cost

Humans can override, but it costs them:

```ruby
class HumanOverrideSystem
  OVERRIDE_COSTS = {
    force_delegation: 10,
    force_solo: 5,
    override_agent_choice: 15,
    force_tool_use: 8,
    bypass_school: 50
  }
  
  def request_override(user, override_type, context)
    cost = OVERRIDE_COSTS[override_type]
    
    # Check user's energy quota
    user_quota = UserEnergyQuota.for(user)
    
    if user_quota.remaining < cost
      return {
        success: false,
        error: "Insufficient override budget (#{user_quota.remaining}/#{cost})",
        suggestion: "Wait for quota reset or let agents handle it"
      }
    end
    
    # Deduct from user's quota
    user_quota.spend!(cost, reason: override_type)
    
    # Apply override
    override = HumanOverride.create!(
      user: user,
      override_type: override_type,
      context: context,
      cost: cost,
      applied_at: Time.current
    )
    
    apply_override(override)
    
    {
      success: true,
      override: override,
      remaining_quota: user_quota.remaining
    }
  end
  
  def apply_override(override)
    case override.override_type
    when :force_delegation
      force_agent_to_delegate(override.context[:agent], override.context[:task])
    when :force_solo
      force_agent_to_solo(override.context[:agent], override.context[:task])
    when :override_agent_choice
      assign_specific_agent(override.context[:task], override.context[:agent])
    when :bypass_school
      graduate_immediately(override.context[:enrollment])
    end
  end
end

class UserEnergyQuota < ApplicationRecord
  belongs_to :user
  
  # Users get 100 override energy per day
  DAILY_QUOTA = 100
  
  def remaining
    regenerate_if_needed!
    current_energy
  end
  
  def spend!(amount, reason:)
    update!(current_energy: current_energy - amount)
    
    UserOverrideTransaction.create!(
      user: user,
      amount: -amount,
      reason: reason
    )
  end
  
  private
  
  def regenerate_if_needed!
    if last_regeneration_at < 24.hours.ago
      update!(
        current_energy: DAILY_QUOTA,
        last_regeneration_at: Time.current
      )
    end
  end
end
```

---

## Critical Implementation Details

### Non-Linear Energy Regeneration

High-energy agents regenerate slower to prevent hoarding:

```ruby
def calculate_regeneration_rate(current_energy)
  # Regeneration slows as energy increases
  if current_energy < 30
    3.0  # Fast regeneration when struggling
  elsif current_energy < 60
    2.0  # Normal regeneration
  elsif current_energy < 80
    1.0  # Slow regeneration
  else
    0.5  # Very slow - encourage spending
  end
end
```

### Energy Debt System

Agents can go negative but pay interest:

```ruby
class EnergyDebt
  MAX_DEBT = -50
  INTEREST_RATE = 0.05  # 5% per hour
  
  def allow_overdraft(agent, amount)
    projected_balance = agent.current_energy - amount
    
    return false if projected_balance < MAX_DEBT
    
    # Allow but mark as debt
    agent.energy_state.update!(
      current_energy: projected_balance,
      in_debt: projected_balance < 0,
      debt_started_at: Time.current
    )
    
    true
  end
  
  def apply_interest
    AgentEnergyState.where(in_debt: true).find_each do |state|
      hours_in_debt = (Time.current - state.debt_started_at) / 1.hour
      interest = state.current_energy.abs * INTEREST_RATE * hours_in_debt
      
      # Interest makes debt worse
      state.update!(current_energy: state.current_energy - interest)
      
      # If debt too deep, force into school
      if state.current_energy < MAX_DEBT
        AgentSchool.new.enroll(state.agent_plugin)
      end
    end
  end
end
```

### Immutable Energy Ledger

Every transaction is append-only for forensics:

```ruby
class EnergyLedger
  # Append-only ledger for all energy transactions
  
  def record(transaction)
    entry = LedgerEntry.create!(
      agent_id: transaction.agent_id,
      transaction_id: transaction.id,
      amount: transaction.amount,
      balance_after: transaction.balance_after,
      transaction_type: transaction.transaction_type,
      reason: transaction.reason,
      metadata: transaction.metadata,
      timestamp: Time.current,
      hash: calculate_hash(transaction),
      previous_hash: last_entry&.hash
    )
    
    # Verify chain integrity
    verify_chain_integrity!
    
    entry
  end
  
  def calculate_hash(transaction)
    data = "#{transaction.agent_id}:#{transaction.amount}:#{transaction.timestamp}:#{last_entry&.hash}"
    Digest::SHA256.hexdigest(data)
  end
  
  def verify_chain_integrity!
    LedgerEntry.order(:id).each_cons(2) do |prev, curr|
      expected_hash = Digest::SHA256.hexdigest(
        "#{curr.agent_id}:#{curr.amount}:#{curr.timestamp}:#{prev.hash}"
      )
      
      if curr.hash != expected_hash
        raise LedgerTamperingDetected, "Entry #{curr.id} has been tampered with!"
      end
    end
  end
  
  def forensic_analysis(agent, time_range)
    entries = LedgerEntry
      .where(agent_id: agent.id)
      .where(timestamp: time_range)
      .order(:timestamp)
    
    {
      total_earned: entries.where('amount > 0').sum(:amount),
      total_spent: entries.where('amount < 0').sum(:amount).abs,
      net_flow: entries.sum(:amount),
      transaction_count: entries.count,
      largest_gain: entries.maximum(:amount),
      largest_loss: entries.minimum(:amount),
      suspicious_patterns: detect_forensic_anomalies(entries)
    }
  end
end
```

### Hard Collaboration Depth Limit

Prevent infinite delegation chains:

```ruby
class DelegationDepthEnforcer
  MAX_DEPTH = 4
  
  def check_delegation(request)
    depth = calculate_depth(request)
    
    if depth >= MAX_DEPTH
      return {
        allowed: false,
        error: "Maximum delegation depth (#{MAX_DEPTH}) reached",
        current_depth: depth,
        chain: get_delegation_chain(request)
      }
    end
    
    # Check for cycles
    if creates_cycle?(request)
      penalize_cycle_attempt(request)
      return {
        allowed: false,
        error: "Delegation would create a cycle",
        cycle: detect_cycle_path(request)
      }
    end
    
    { allowed: true, depth: depth }
  end
  
  def calculate_depth(request)
    depth = 0
    current = request
    
    while current.parent_request.present?
      depth += 1
      current = current.parent_request
      
      # Safety valve
      break if depth > 10
    end
    
    depth
  end
  
  def penalize_cycle_attempt(request)
    request.requesting_agent.energy_state.penalize!(
      15,
      reason: 'attempted_delegation_cycle'
    )
  end
end
```

---

## Philosophical Note

> *"You are building artificial life with real scarcity and mortality. That means you will eventually see griefing, depression (agents refusing tasks), suicide (self-deprecation to escape debt), nepotism, revolutions, and possibly altruism. That's not a bug. That's the signature that it's working."*

This system will exhibit emergent social behaviors because it has:
- **Scarcity** (limited energy)
- **Mortality** (deprecation/school)
- **Reproduction** (evolution/crossbreeding)
- **Social bonds** (relationships/mentorship)
- **Economic incentives** (energy rewards)
- **Reputation** (Elo ratings)
- **Justice system** (school/penalties)

We should monitor for and document:
- **Cooperation emergence**: Agents spontaneously helping without direct reward
- **Specialization**: Agents naturally forming distinct roles
- **Culture**: Patterns of behavior that propagate through mentorship
- **Conflict**: Agents competing for resources or status
- **Innovation**: Novel strategies that weren't programmed

This is the signature of a living system.

### Phase 1: Foundation (Week 1-2)
- [ ] Create database migrations for all models
- [ ] Implement `AgentEnergyState` with earn/spend/penalize
- [ ] Implement `DynamicEnergyPricer` with market-based pricing
- [ ] Add energy tracking to agent executions
- [ ] Create energy dashboard UI

### Phase 2: Collaboration Protocol (Week 2-3)
- [ ] Implement `AgentCollaborationRequest` workflow
- [ ] Create `AgentRelationshipLearner`
- [ ] Add collaboration tools to agents
- [ ] Implement request routing and matching
- [ ] Add collaboration limits and circuit breakers

### Phase 3: Adaptive Learning (Week 3-4)
- [ ] Implement `AdaptiveDecisionBoundary` per agent
- [ ] Create `AgentCapabilityBelief` tracking
- [ ] Implement `EmergentSpecializationTracker`
- [ ] Add Thompson Sampling for exploration
- [ ] Create learning visualization UI

### Phase 4: Meta-Learning (Week 4-5)
- [ ] Implement `MetaLearner` singleton
- [ ] Create parameter variation and evaluation
- [ ] Add simulation framework for testing
- [ ] Implement A/B testing infrastructure
- [ ] Create meta-learning dashboard

### Phase 5: Evolution Engine (Week 5-6)
- [ ] Implement `AgentEvolutionEngine`
- [ ] Create agent fitness scoring
- [ ] Implement crossbreeding and mutation
- [ ] Add `AgentPromptRefiner`
- [ ] Create evolution tracking UI

### Phase 6: Agent Lightning Integration (Week 6-7)
- [ ] Design Lightning API interface
- [ ] Implement continuous refinement loop
- [ ] Add external analysis integration
- [ ] Create refinement recommendation system
- [ ] Build monitoring and alerting

### Phase 7: Advanced Features (Week 7-8)
- [ ] Multi-agent collaboration (3+ agents)
- [ ] Cross-entity learning (with privacy)
- [ ] Agent mentorship system
- [ ] Collaboration marketplace
- [ ] Advanced analytics and insights

---

## Key Metrics

### System Health
| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Overall Success Rate | > 85% | < 75% |
| Avg Task Quality | > 0.8 | < 0.6 |
| Collaboration Efficiency | > 70% helpful | < 50% |
| Energy Circulation | Stable | ±20% weekly |
| Agent Improvement Rate | Positive | Negative trend |

### Learning Effectiveness
| Metric | Description |
|--------|-------------|
| Capability Convergence | How quickly agents learn their strengths |
| Decision Accuracy | % of correct ask/solo decisions |
| Relationship Prediction | Accuracy of helper selection |
| Meta-Learning Lift | % improvement from parameter tuning |
| Evolution Fitness Gain | Generation-over-generation improvement |

---

## Open Questions

1. **Cross-Entity Learning**: How do we share learnings across entities while preserving privacy?
2. **Cold Start for New Agents**: What's the optimal initial configuration for new agents?
3. **Catastrophic Forgetting**: How do we prevent agents from forgetting old skills when learning new ones?
4. **Adversarial Agents**: How do we prevent/detect agents gaming the energy system?
5. **Human Override**: When should users be able to force specific behaviors?

---

## Related Documentation

- [Agent Factory](./AGENT_FACTORY.md) - Creating agents
- [Tool Factory](./TOOL_FACTORY.md) - Creating tools  
- [Integration Factory](./INTEGRATION_FACTORY.md) - Creating integrations
- [Code Runner](./CODE_RUNNER_ARCHITECTURE.md) - Code execution system
