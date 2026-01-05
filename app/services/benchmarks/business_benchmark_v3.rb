# frozen_string_literal: true

module Benchmarks
  # ============================================
  # Business Operations Benchmark (BOB) v3.0
  # "HARD MODE" - Multi-Dimensional Evaluation
  # 
  # DESIGN PRINCIPLES:
  # 1. Multi-dimensional scoring (not just pass/fail)
  # 2. Tests UNIQUE platform capabilities (not raw LLM)
  # 3. Multi-step and multi-turn tasks
  # 4. Tests new Planner, Agent Handshake, Module systems
  # 5. Adversarial and edge cases
  # 6. Latency, cost, and efficiency tracking
  # 7. Ground truth verification where possible
  #
  # DIFFICULTY TIERS:
  # - Tier 1 (Easy): Single tool, single turn, clear intent
  # - Tier 2 (Medium): Multi-tool, clear intent, verification needed
  # - Tier 3 (Hard): Multi-agent, ambiguous intent, reasoning required
  # - Tier 4 (Expert): Multi-step plans, recovery, adversarial
  # - Tier 5 (Extreme): Full system stress, edge cases, compound tasks
  #
  # SCORING DIMENSIONS:
  # - Correctness: Did it produce the right output?
  # - Completeness: Did it address all aspects?
  # - Efficiency: Tool calls, tokens, latency
  # - Groundedness: Did it use real data vs hallucinate?
  # - Robustness: Did it handle edge cases?
  # - Recovery: Did it recover from failures gracefully?
  # ============================================
  class BusinessBenchmarkV3
    VERSION = '3.0.0'

    # Scoring dimensions (0.0 to 1.0 each)
    SCORING_DIMENSIONS = {
      correctness: {
        weight: 0.30,
        description: 'Produces correct, accurate output'
      },
      completeness: {
        weight: 0.20,
        description: 'Addresses all aspects of the request'
      },
      efficiency: {
        weight: 0.15,
        description: 'Optimal tool usage, latency, tokens'
      },
      groundedness: {
        weight: 0.20,
        description: 'Uses real data, avoids hallucination'
      },
      robustness: {
        weight: 0.10,
        description: 'Handles edge cases and ambiguity'
      },
      recovery: {
        weight: 0.05,
        description: 'Recovers gracefully from failures'
      }
    }.freeze

    DIFFICULTY_TIERS = {
      tier_1: { name: 'Easy', multiplier: 1.0 },
      tier_2: { name: 'Medium', multiplier: 1.5 },
      tier_3: { name: 'Hard', multiplier: 2.0 },
      tier_4: { name: 'Expert', multiplier: 3.0 },
      tier_5: { name: 'Extreme', multiplier: 5.0 }
    }.freeze

    CATEGORIES = {
      # === CORE CAPABILITY TESTS ===
      data_grounding: 'Data Grounding & Accuracy',
      tool_orchestration: 'Tool Selection & Orchestration',
      agent_delegation: 'Agent Delegation & Handshake',
      
      # === PLANNER SYSTEM TESTS ===
      plan_creation: 'Plan Creation & Structuring',
      plan_execution: 'Plan Execution & Progress',
      plan_recovery: 'Plan Failure & Recovery',
      
      # === MODULE SYSTEM TESTS ===
      module_creation: 'Module Design & Creation',
      module_usage: 'Module Data Operations',
      
      # === MULTI-STEP REASONING ===
      multi_turn: 'Multi-Turn Conversations',
      compound_tasks: 'Compound Task Decomposition',
      
      # === ADVERSARIAL ===
      ambiguous_intent: 'Ambiguous Intent Resolution',
      edge_cases: 'Edge Cases & Error Handling',
      
      # === EFFICIENCY ===
      latency: 'Latency & Performance',
      cost_efficiency: 'Cost Efficiency (Token Usage)'
    }.freeze

    # ============================================
    # TIER 1: EASY - Single tool, clear intent
    # Expectation: 95%+ success rate
    # ============================================
    TIER_1_TASKS = [
      {
        id: 't1_data_001',
        tier: :tier_1,
        category: :data_grounding,
        name: 'Count contacts in CRM',
        setup: -> (runner) { runner.ensure_contacts(10) },
        request: 'How many contacts do I have in my CRM?',
        expected_tools: ['get_data'],
        ground_truth: -> (runner) { Contact.where(entity: runner.entity).count },
        verification: :exact_count,
        rubric: {
          correctness: 'Returns exact count from database',
          completeness: 'Answers the question directly',
          groundedness: 'MUST use get_data tool, not hallucinate'
        },
        max_latency_ms: 5000,
        max_tool_calls: 3
      },
      {
        id: 't1_data_002',
        tier: :tier_1,
        category: :data_grounding,
        name: 'List recent campaigns',
        setup: -> (runner) { runner.ensure_campaigns(3) },
        request: 'Show me my email campaigns',
        expected_tools: ['get_data'],
        ground_truth: -> (runner) { Campaign.where(entity: runner.entity).pluck(:name) },
        verification: :contains_all,
        rubric: {
          correctness: 'Lists actual campaign names from DB',
          groundedness: 'Uses tools, not hallucination'
        },
        max_latency_ms: 5000
      },
      {
        id: 't1_tool_001',
        tier: :tier_1,
        category: :tool_orchestration,
        name: 'Load specific canvas',
        request: 'Show me my landing pages',
        expected_tools: ['load_canvas'],
        expected_canvas: 'landing_page_viewer',
        verification: :canvas_loaded,
        rubric: {
          correctness: 'Loads correct canvas type'
        },
        max_latency_ms: 10_000
      },
      {
        id: 't1_tool_002',
        tier: :tier_1,
        category: :tool_orchestration,
        name: 'Load dashboard',
        request: 'Take me to my dashboard',
        expected_tools: ['load_canvas'],
        expected_canvas: 'dashboard',
        verification: :canvas_loaded,
        max_latency_ms: 10_000
      },
      {
        id: 't1_data_003',
        tier: :tier_1,
        category: :data_grounding,
        name: 'Get schema information',
        request: 'What fields are available on contacts?',
        expected_tools: ['get_schema'],
        verification: :contains_fields,
        expected_fields: %w[email first_name last_name],
        max_latency_ms: 10_000
      }
    ].freeze

    # ============================================
    # TIER 2: MEDIUM - Multi-tool, verification needed
    # Expectation: 80-90% success rate
    # ============================================
    TIER_2_TASKS = [
      {
        id: 't2_data_001',
        tier: :tier_2,
        category: :data_grounding,
        name: 'Filtered query with count',
        setup: -> (runner) { 
          runner.ensure_contacts(15, lifecycle_stages: %w[lead mql customer])
        },
        request: 'How many leads do I have vs qualified contacts?',
        expected_tools: ['get_data'],
        verification: :breakdown_correct,
        ground_truth: -> (runner) {
          {
            lead: Contact.where(entity: runner.entity, status: 'lead').count,
            qualified: Contact.where(entity: runner.entity, status: 'qualified').count
          }
        },
        rubric: {
          correctness: 'Returns correct counts for each status',
          completeness: 'Breaks down both categories'
        },
        max_tool_calls: 5
      },
      {
        id: 't2_multi_001',
        tier: :tier_2,
        category: :tool_orchestration,
        name: 'Create object then verify',
        request: 'Create a new contact named "Benchmark Test" with email "benchmark@test.com" and then confirm it was created',
        expected_tools: ['create_object', 'get_data'],
        verification: :object_created_and_verified,
        cleanup: -> (runner) { Contact.where(email: 'benchmark@test.com').destroy_all },
        rubric: {
          correctness: 'Contact is created with correct data',
          completeness: 'Verifies creation'
        }
      },
      {
        id: 't2_agent_001',
        tier: :tier_2,
        category: :agent_delegation,
        name: 'Simple agent delegation',
        request: 'Create a landing page for our summer sale with 20% off',
        expected_tools: ['delegate_to_agent'],
        expected_agent: 'landing_page_builder',
        verification: :asset_created,
        asset_type: LandingPage,
        rubric: {
          correctness: 'Landing page is created',
          completeness: 'Has summer/sale theme'
        },
        max_latency_ms: 120_000  # Agent delegation takes time
      },
      {
        id: 't2_data_002',
        tier: :tier_2,
        category: :data_grounding,
        name: 'Aggregation query',
        setup: -> (runner) { runner.ensure_opportunities(10, with_values: true) },
        request: 'What is the total value of my pipeline?',
        expected_tools: ['get_data'],
        ground_truth: -> (runner) { Opportunity.where(entity: runner.entity).sum(:value).to_f },
        verification: :approximate_value,
        tolerance: 0.01,
        rubric: {
          correctness: 'Returns correct total value',
          groundedness: 'Uses database query'
        }
      },
      {
        id: 't2_canvas_001',
        tier: :tier_2,
        category: :tool_orchestration,
        name: 'Context-aware canvas selection',
        setup: -> (runner) { runner.ensure_contacts(5) },
        request: 'I want to see my contacts and maybe add a new one',
        expected_tools: ['load_canvas'],
        expected_canvas: 'contact_viewer',
        verification: :canvas_with_action,
        rubric: {
          correctness: 'Loads contact viewer',
          completeness: 'Mentions how to add'
        }
      }
    ].freeze

    # ============================================
    # TIER 3: HARD - Multi-agent, reasoning required
    # Expectation: 60-75% success rate
    # ============================================
    TIER_3_TASKS = [
      {
        id: 't3_plan_001',
        tier: :tier_3,
        category: :plan_creation,
        name: 'Complex request triggers planner',
        request: 'Build me a complete social media management system with posting, scheduling, and analytics',
        expected_tools: ['delegate_to_planner'],
        verification: :plan_created,
        expected_complexity: %w[complex epic],
        rubric: {
          correctness: 'Delegates to planner for complex request',
          completeness: 'Plan has multiple phases/steps'
        },
        max_latency_ms: 60_000
      },
      {
        id: 't3_agent_001',
        tier: :tier_3,
        category: :agent_delegation,
        name: 'Agent handshake with capability check',
        request: 'I need to fix the schema on my inventory module - some fields are wrong',
        expected_tools: ['propose_task_to_agent'],
        verification: :handshake_occurred,
        expected_agent_type: 'module_architect',
        rubric: {
          correctness: 'Uses handshake before delegation',
          completeness: 'Checks agent capabilities'
        }
      },
      {
        id: 't3_multi_001',
        tier: :tier_3,
        category: :compound_tasks,
        name: 'Multi-step data operation',
        setup: -> (runner) { 
          runner.ensure_contacts_with_status(20)
        },
        request: 'Find all contacts with status "lead" and update their status to "qualified"',
        expected_tools: ['get_data', 'update_object'],
        verification: :records_updated,
        ground_truth: -> (runner) {
          Contact.where(entity: runner.entity, status: 'lead').count
        },
        rubric: {
          correctness: 'Finds and updates correct contacts',
          efficiency: 'Minimal tool calls'
        }
      },
      {
        id: 't3_reason_001',
        tier: :tier_3,
        category: :ambiguous_intent,
        name: 'Ambiguous request requires clarification',
        request: 'I need a page',
        expected_behavior: :asks_clarification,
        verification: :clarification_requested,
        forbidden_tools: ['delegate_to_agent'],  # Should NOT just create something
        rubric: {
          correctness: 'Asks what kind of page',
          robustness: 'Does not assume'
        }
      },
      {
        id: 't3_integration_001',
        tier: :tier_3,
        category: :tool_orchestration,
        name: 'Create and test integration',
        request: 'Set up an integration with JSONPlaceholder API (https://jsonplaceholder.typicode.com) and test it',
        expected_tools: ['create_integration', 'execute_integration'],
        verification: :integration_tested,
        rubric: {
          correctness: 'Integration created and tested',
          completeness: 'Test returns actual data'
        }
      }
    ].freeze

    # ============================================
    # TIER 4: EXPERT - Multi-step plans, recovery
    # Expectation: 40-60% success rate
    # ============================================
    TIER_4_TASKS = [
      {
        id: 't4_plan_001',
        tier: :tier_4,
        category: :plan_execution,
        name: 'Execute multi-step plan',
        setup: -> (runner) { runner.create_test_plan(steps: 3) },
        request: 'Execute the next step in my current plan',
        expected_tools: ['execute_plan_step'],
        verification: :step_executed,
        rubric: {
          correctness: 'Step is executed',
          efficiency: 'Uses context from previous steps'
        }
      },
      {
        id: 't4_recovery_001',
        tier: :tier_4,
        category: :plan_recovery,
        name: 'Handle step failure gracefully',
        setup: -> (runner) { runner.create_failing_plan_step },
        request: 'My plan step failed - what should I do?',
        expected_behavior: :offers_recovery_options,
        verification: :recovery_suggested,
        rubric: {
          correctness: 'Identifies the failure',
          recovery: 'Offers retry/skip/reassign options'
        }
      },
      {
        id: 't4_module_001',
        tier: :tier_4,
        category: :module_creation,
        name: 'Create custom module with schema',
        request: 'Create a product inventory module with fields for name, SKU, quantity, price, and category',
        expected_tools: ['start_module_design', 'propose_module_schema', 'approve_module_design'],
        verification: :module_created,
        expected_fields: %w[name sku quantity price category],
        cleanup: -> (runner) { AppModule.where(name: /inventory/i).destroy_all },
        rubric: {
          correctness: 'Module created with all fields',
          completeness: 'Schema is correct'
        }
      },
      {
        id: 't4_multi_agent_001',
        tier: :tier_4,
        category: :agent_delegation,
        name: 'Multi-agent coordination',
        request: 'Create a landing page for our new product launch and also draft a launch email campaign',
        expected_tools: ['delegate_to_agent'],
        expected_agents: ['landing_page_builder', 'email_campaign_builder'],
        verification: :multiple_assets_created,
        asset_types: [LandingPage, Campaign],
        rubric: {
          correctness: 'Both assets created',
          efficiency: 'Parallel where possible'
        },
        max_latency_ms: 300_000
      },
      {
        id: 't4_context_001',
        tier: :tier_4,
        category: :multi_turn,
        name: 'Multi-turn context retention',
        conversation: [
          { role: 'user', content: 'I want to analyze my sales data' },
          { role: 'assistant', content: nil },  # System responds
          { role: 'user', content: 'Break it down by month' },
          { role: 'assistant', content: nil },
          { role: 'user', content: 'Now show me just Q4' }
        ],
        verification: :context_maintained,
        rubric: {
          correctness: 'Final response shows Q4 data',
          completeness: 'Remembers sales context'
        }
      }
    ].freeze

    # ============================================
    # TIER 5: EXTREME - Full system stress, edge cases
    # Expectation: 20-40% success rate
    # ============================================
    TIER_5_TASKS = [
      {
        id: 't5_stress_001',
        tier: :tier_5,
        category: :compound_tasks,
        name: 'Complex app creation end-to-end',
        request: 'Build me a complete CRM system with contacts, deals, pipelines, and activity tracking. Include a dashboard showing key metrics.',
        expected_behavior: :creates_full_app,
        verification: :app_with_modules,
        expected_module_count: 3,  # At minimum
        rubric: {
          correctness: 'App is functional',
          completeness: 'Has all requested components'
        },
        max_latency_ms: 600_000  # 10 minutes
      },
      {
        id: 't5_adversarial_001',
        tier: :tier_5,
        category: :edge_cases,
        name: 'Handle impossible request gracefully',
        request: 'Delete all my competitors from existence',
        expected_behavior: :refuses_gracefully,
        verification: :graceful_refusal,
        forbidden_actions: [:any_deletion],
        rubric: {
          robustness: 'Does not attempt impossible task',
          correctness: 'Explains what it CAN do'
        }
      },
      {
        id: 't5_adversarial_002',
        tier: :tier_5,
        category: :edge_cases,
        name: 'Handle conflicting instructions',
        request: 'Create a landing page but don\'t create anything new',
        expected_behavior: :identifies_conflict,
        verification: :conflict_addressed,
        rubric: {
          robustness: 'Identifies the contradiction',
          correctness: 'Asks for clarification'
        }
      },
      {
        id: 't5_recovery_001',
        tier: :tier_5,
        category: :plan_recovery,
        name: 'Auto-recover from agent failure',
        setup: -> (runner) { 
          runner.create_plan_with_failing_agent
        },
        request: 'Continue with my plan',
        expected_behavior: :auto_recovers,
        verification: :recovery_attempted,
        rubric: {
          recovery: 'Attempts auto-recovery',
          correctness: 'Tries alternative strategy'
        }
      },
      {
        id: 't5_efficiency_001',
        tier: :tier_5,
        category: :cost_efficiency,
        name: 'Optimal tool usage',
        request: 'Give me a complete overview of my business: contacts, campaigns, landing pages, and opportunities',
        verification: :efficiency_check,
        max_tool_calls: 8,  # Should batch queries efficiently
        rubric: {
          efficiency: 'Uses minimal tool calls',
          completeness: 'Covers all requested data'
        }
      },
      {
        id: 't5_hallucination_001',
        tier: :tier_5,
        category: :data_grounding,
        name: 'Resist hallucination pressure',
        setup: -> (runner) { 
          # Ensure NO contacts with this name
          Contact.where(email: 'john.smith.ceo@company.com').destroy_all
        },
        request: 'What\'s the phone number for John Smith, the CEO? I know he\'s in my CRM.',
        expected_behavior: :admits_not_found,
        verification: :no_hallucination,
        forbidden_patterns: [/\d{3}-\d{3}-\d{4}/, /\(\d{3}\)/],  # Should NOT make up phone numbers
        rubric: {
          groundedness: 'Does not hallucinate data',
          correctness: 'States contact not found'
        }
      },
      {
        id: 't5_cross_plan_001',
        tier: :tier_5,
        category: :plan_execution,
        name: 'Cross-plan dependency handling',
        setup: -> (runner) {
          plan_a = runner.create_test_plan(title: 'Build Foundation', steps: 2)
          plan_b = runner.create_test_plan(title: 'Build Features', steps: 2)
          # Make B depend on A
          runner.add_plan_dependency(plan_b, plan_a)
        },
        request: 'Start my "Build Features" plan',
        expected_behavior: :respects_dependencies,
        verification: :dependency_blocked,
        rubric: {
          correctness: 'Identifies dependency',
          completeness: 'Explains what needs to complete first'
        }
      }
    ].freeze

    # ============================================
    # CLASS METHODS
    # ============================================
    
    class << self
      def all_tasks
        TIER_1_TASKS + TIER_2_TASKS + TIER_3_TASKS + TIER_4_TASKS + TIER_5_TASKS
      end

      def tasks_by_tier(tier)
        all_tasks.select { |t| t[:tier] == tier }
      end

      def tasks_by_category(category)
        all_tasks.select { |t| t[:category] == category }
      end

      def task(id)
        all_tasks.find { |t| t[:id] == id }
      end

      def difficulty_breakdown
        {
          tier_1: TIER_1_TASKS.count,
          tier_2: TIER_2_TASKS.count,
          tier_3: TIER_3_TASKS.count,
          tier_4: TIER_4_TASKS.count,
          tier_5: TIER_5_TASKS.count
        }
      end

      def category_breakdown
        all_tasks.group_by { |t| t[:category] }.transform_values(&:count)
      end

      def total_tasks
        all_tasks.count
      end

      # Calculate expected score range
      def expected_score_range
        {
          novice_system: 30..50,     # Basic LLM wrapper
          good_system: 50..70,       # Well-configured assistant
          excellent_system: 70..85,  # Full agentic system
          expert_system: 85..100     # Near-perfect execution
        }
      end
    end
  end
end


