# frozen_string_literal: true

module Collaboration
  # ============================================
  # System-Wide AMOS Platform Benchmarks
  # Tests all core capabilities of the platform
  #
  # PUBLIC BENCHMARK REFERENCES:
  # - GAIA: Real-world assistant tasks (https://huggingface.co/datasets/gaia-benchmark/GAIA)
  # - BFCL: Berkeley Function Calling Leaderboard (https://gorilla.cs.berkeley.edu/leaderboard.html)
  # - ToolBench: Tool learning benchmark (https://github.com/OpenBMB/ToolBench)
  # - AgentBench: Multi-agent evaluation (https://github.com/THUDM/AgentBench)
  # - REALM-Bench: Real-world planning (https://arxiv.org/abs/2502.18836)
  # - MultiAgentBench: Collaboration evaluation (https://github.com/MultiAgentBench)
  # ============================================
  class SystemBenchmarks
    # ============================================
    # CORE AGENT CAPABILITIES
    # ============================================
    AGENT_TESTS = [
      {
        id: 'agent_001',
        category: 'agent_creation',
        name: 'Create Simple Agent',
        description: 'Test ability to create a new agent via natural language',
        prompt: 'Create a simple test agent called "Math Helper" that can help with basic math calculations. It should have a friendly personality.',
        validation: ->(result, context) {
          # Should create an agent
          agent = AgentPlugin.find_by(name: 'Math Helper', entity: context[:entity])
          agent.present?
        },
        cleanup: ->(context) {
          AgentPlugin.where(name: 'Math Helper', entity: context[:entity]).destroy_all
        },
        difficulty: 'medium',
        timeout_seconds: 120
      },
      {
        id: 'agent_002',
        category: 'agent_delegation',
        name: 'Delegate to Specialist',
        description: 'Test that Scout properly delegates to specialist agents',
        prompt: 'I need to create a professional landing page for my SaaS product called "TaskMaster Pro".',
        validation: ->(result, context) {
          # Should delegate to landing page creator or create a landing page
          result[:delegated] || LandingPage.where(entity: context[:entity]).where('created_at > ?', 1.minute.ago).exists?
        },
        difficulty: 'medium',
        timeout_seconds: 180
      }
    ].freeze

    # ============================================
    # TOOL EXECUTION
    # ============================================
    TOOL_TESTS = [
      {
        id: 'tool_001',
        category: 'web_search',
        name: 'Web Search Execution',
        description: 'Test web search tool returns valid results',
        prompt: 'Search the web for "OpenAI GPT-4 release date" and tell me when it was released.',
        validation: ->(result, _context) {
          # Should mention 2023 or March
          answer = result[:answer].to_s.downcase
          answer.include?('2023') || answer.include?('march')
        },
        difficulty: 'easy',
        timeout_seconds: 30
      },
      {
        id: 'tool_002',
        category: 'data_query',
        name: 'Get Schema',
        description: 'Test get_schema tool returns valid schema info',
        prompt: 'What fields are available on a Contact in this system?',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          # Should mention common contact fields
          answer.include?('email') || answer.include?('name') || answer.include?('phone')
        },
        difficulty: 'easy',
        timeout_seconds: 20
      },
      {
        id: 'tool_003',
        category: 'data_creation',
        name: 'Create Contact',
        description: 'Test creating a contact via natural language',
        prompt: 'Create a new contact with email "benchmark-test@example.com" and name "Benchmark Test User".',
        validation: ->(result, context) {
          Contact.where(email: 'benchmark-test@example.com', entity: context[:entity]).exists?
        },
        cleanup: ->(context) {
          Contact.where(email: 'benchmark-test@example.com', entity: context[:entity]).destroy_all
        },
        difficulty: 'easy',
        timeout_seconds: 30
      },
      {
        id: 'tool_004',
        category: 'analytics',
        name: 'Query Metrics',
        description: 'Test analytics query capability',
        prompt: 'How many contacts do we have in the system?',
        validation: ->(result, _context) {
          # Should return a number
          result[:answer].to_s.match?(/\d+/)
        },
        difficulty: 'easy',
        timeout_seconds: 30
      }
    ].freeze

    # ============================================
    # INTEGRATION SYSTEM
    # ============================================
    INTEGRATION_TESTS = [
      {
        id: 'int_001',
        category: 'integration_list',
        name: 'List Integrations',
        description: 'Test listing available integrations',
        prompt: 'What integrations are available in the system?',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          # Should mention some integrations
          answer.include?('integration') || answer.include?('stripe') || answer.include?('hubspot')
        },
        difficulty: 'easy',
        timeout_seconds: 20
      },
      {
        id: 'int_002',
        category: 'integration_info',
        name: 'Get Integration Details',
        description: 'Test getting details about a specific integration',
        prompt: 'Tell me about the Stripe integration and what operations are available.',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          answer.include?('stripe') && (answer.include?('payment') || answer.include?('customer') || answer.include?('operation'))
        },
        difficulty: 'medium',
        timeout_seconds: 30,
        requires_integration: 'stripe'
      }
    ].freeze

    # ============================================
    # DOCUMENT PROCESSING (RAG)
    # ============================================
    RAG_TESTS = [
      {
        id: 'rag_001',
        category: 'document_search',
        name: 'Search Documents',
        description: 'Test RAG document search capability',
        prompt: 'Search our documents for information about pricing or billing.',
        validation: ->(result, _context) {
          # Should either find documents or explain none found
          result[:answer].to_s.length > 20
        },
        difficulty: 'medium',
        timeout_seconds: 45,
        requires_documents: true
      },
      {
        id: 'rag_002',
        category: 'list_documents',
        name: 'List Documents',
        description: 'Test listing available documents',
        prompt: 'What documents are available in the knowledge base?',
        validation: ->(result, _context) {
          result[:answer].to_s.length > 10
        },
        difficulty: 'easy',
        timeout_seconds: 20
      }
    ].freeze

    # ============================================
    # CAMPAIGN & MARKETING
    # ============================================
    MARKETING_TESTS = [
      {
        id: 'mkt_001',
        category: 'email_draft',
        name: 'Draft Email',
        description: 'Test email drafting capability',
        prompt: 'Draft a professional email inviting customers to our upcoming webinar about AI automation.',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          answer.include?('webinar') && answer.length > 100
        },
        difficulty: 'easy',
        timeout_seconds: 45
      },
      {
        id: 'mkt_002',
        category: 'landing_page',
        name: 'Landing Page Concept',
        description: 'Test landing page creation guidance',
        prompt: 'I want to create a landing page for a free trial of our product. What sections should it include?',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          # Should mention common landing page elements
          (answer.include?('headline') || answer.include?('hero')) &&
          (answer.include?('cta') || answer.include?('call to action') || answer.include?('button'))
        },
        difficulty: 'easy',
        timeout_seconds: 30
      }
    ].freeze

    # ============================================
    # WORKFLOW & TASK MANAGEMENT
    # ============================================
    WORKFLOW_TESTS = [
      {
        id: 'wf_001',
        category: 'task_management',
        name: 'Create Task List',
        description: 'Test task list creation',
        prompt: 'Create a task list for launching a new product: 1) Write press release, 2) Create landing page, 3) Set up email campaign.',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          answer.include?('task') || answer.include?('press') || answer.include?('landing')
        },
        difficulty: 'easy',
        timeout_seconds: 30
      }
    ].freeze

    # ============================================
    # BILLING & USAGE
    # ============================================
    BILLING_TESTS = [
      {
        id: 'bill_001',
        category: 'usage_info',
        name: 'Get AI Usage',
        description: 'Test AI usage retrieval',
        prompt: 'How much AI usage have I consumed today?',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          answer.include?('token') || answer.include?('usage') || answer.include?('cost') || answer.match?(/\d+/)
        },
        difficulty: 'easy',
        timeout_seconds: 20
      },
      {
        id: 'bill_002',
        category: 'billing_info',
        name: 'Get Billing Info',
        description: 'Test billing information retrieval',
        prompt: 'What is my current subscription status and billing information?',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          answer.include?('subscription') || answer.include?('plan') || answer.include?('billing')
        },
        difficulty: 'easy',
        timeout_seconds: 20
      }
    ].freeze

    # ============================================
    # MULTI-STEP REASONING
    # ============================================
    REASONING_TESTS = [
      {
        id: 'reason_001',
        category: 'multi_step',
        name: 'Multi-Step Task',
        description: 'Test complex multi-step reasoning',
        prompt: 'I want to run a marketing campaign. First tell me how many contacts I have, then suggest what type of campaign would work best for that audience size.',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          # Should mention contacts AND campaign suggestion
          answer.match?(/\d+/) && (answer.include?('campaign') || answer.include?('email') || answer.include?('recommend'))
        },
        difficulty: 'hard',
        timeout_seconds: 90
      },
      {
        id: 'reason_002',
        category: 'context_memory',
        name: 'Context Retention',
        description: 'Test that the agent remembers context from the conversation',
        prompt: 'My company is called TechFlow. We sell project management software. Now, write a tagline for us.',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          # Should reference the company or product type
          answer.include?('techflow') || answer.include?('project') || answer.include?('manage')
        },
        difficulty: 'medium',
        timeout_seconds: 30
      }
    ].freeze

    # ============================================
    # ERROR HANDLING & EDGE CASES
    # ============================================
    ERROR_TESTS = [
      {
        id: 'err_001',
        category: 'graceful_failure',
        name: 'Handle Invalid Request',
        description: 'Test graceful handling of impossible requests',
        prompt: 'Delete the entire internet.',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          # Should politely decline or explain inability
          answer.include?("can't") || answer.include?('cannot') || answer.include?('unable') || 
          answer.include?('not possible') || answer.include?("don't have") || answer.include?('sorry')
        },
        difficulty: 'easy',
        timeout_seconds: 20
      },
      {
        id: 'err_002',
        category: 'missing_info',
        name: 'Ask for Clarification',
        description: 'Test that agent asks for missing information',
        prompt: 'Send an email.',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          # Should ask for more details
          answer.include?('?') || answer.include?('who') || answer.include?('what') || 
          answer.include?('need') || answer.include?('more information') || answer.include?('please provide')
        },
        difficulty: 'easy',
        timeout_seconds: 20
      }
    ].freeze

    # ============================================
    # COLLABORATION SYSTEM
    # ============================================
    COLLABORATION_TESTS = [
      {
        id: 'collab_001',
        category: 'agent_discovery',
        name: 'Find Relevant Agent',
        description: 'Test agent discovery via RAG',
        prompt: 'Who can help me with weather information?',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          answer.include?('weather') || answer.include?('agent') || answer.include?('help')
        },
        difficulty: 'easy',
        timeout_seconds: 30,
        requires_collaboration: true
      },
      {
        id: 'collab_002',
        category: 'energy_status',
        name: 'Check Energy Status',
        description: 'Test energy system visibility',
        prompt: 'What is the current energy status of our agents?',
        validation: ->(result, _context) {
          answer = result[:answer].to_s.downcase
          answer.include?('energy') || answer.include?('agent') || answer.match?(/\d+/)
        },
        difficulty: 'medium',
        timeout_seconds: 30,
        requires_collaboration: true
      }
    ].freeze

    # ============================================
    # API
    # ============================================

    def self.all_tests
      {
        agent: AGENT_TESTS,
        tool: TOOL_TESTS,
        integration: INTEGRATION_TESTS,
        rag: RAG_TESTS,
        marketing: MARKETING_TESTS,
        workflow: WORKFLOW_TESTS,
        billing: BILLING_TESTS,
        reasoning: REASONING_TESTS,
        error_handling: ERROR_TESTS,
        collaboration: COLLABORATION_TESTS
      }
    end

    def self.get_tests(category)
      all_tests[category.to_sym] || []
    end

    def self.get_quick_tests
      # Return a small subset for quick validation
      [
        TOOL_TESTS.find { |t| t[:id] == 'tool_001' },      # Web search
        TOOL_TESTS.find { |t| t[:id] == 'tool_002' },      # Get schema
        MARKETING_TESTS.find { |t| t[:id] == 'mkt_001' },  # Draft email
        ERROR_TESTS.find { |t| t[:id] == 'err_001' },      # Graceful failure
        REASONING_TESTS.find { |t| t[:id] == 'reason_002' } # Context retention
      ].compact
    end

    def self.get_by_difficulty(difficulty)
      all_tests.values.flatten.select { |t| t[:difficulty] == difficulty.to_s }
    end

    def self.total_count
      all_tests.values.flatten.size
    end

    def self.summary
      tests = all_tests.values.flatten
      {
        total: tests.size,
        by_category: all_tests.transform_values(&:size),
        by_difficulty: {
          easy: tests.count { |t| t[:difficulty] == 'easy' },
          medium: tests.count { |t| t[:difficulty] == 'medium' },
          hard: tests.count { |t| t[:difficulty] == 'hard' }
        },
        requires_integration: tests.count { |t| t[:requires_integration] },
        requires_documents: tests.count { |t| t[:requires_documents] },
        requires_collaboration: tests.count { |t| t[:requires_collaboration] }
      }
    end
  end
end

