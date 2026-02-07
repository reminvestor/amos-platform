# frozen_string_literal: true

module Benchmarks
  # ============================================
  # Business Operations Benchmark (BOB) v4.0
  # "NIGHTMARE MODE" - Factory Integration Testing
  # 
  # DESIGN PRINCIPLES:
  # 1. Test the FACTORIES that build the platform
  # 2. Verify end-to-end workflows, not just single tools
  # 3. Exact output verification with ground truth
  # 4. Async-aware testing with proper wait mechanisms
  # 5. Cross-factory orchestration tests
  # 6. Real production-realistic scenarios
  #
  # FACTORY CATEGORIES:
  # - Platform Factory: Build complete modules
  # - Tool Factory: Create and execute custom tools
  # - Agent Factory: Create and delegate to agents
  # - Integration Factory: Connect and invoke external APIs
  # - Orchestration: All factories working together
  #
  # VERIFICATION LEVELS:
  # - L1: Tool was called (weak)
  # - L2: Correct tool with correct args (medium)
  # - L3: Expected side effect occurred (strong)
  # - L4: Exact output matches ground truth (exact)
  # - L5: Full workflow completed successfully (integration)
  # ============================================
  class BusinessBenchmarkV4
    VERSION = '4.0.0'

    # Stricter scoring dimensions
    SCORING_DIMENSIONS = {
      correctness: {
        weight: 0.35,
        description: 'Produces correct, verified output'
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
        weight: 0.15,
        description: 'Uses real data, avoids hallucination'
      },
      integration: {
        weight: 0.10,
        description: 'Artifacts created and verified in database'
      },
      recovery: {
        weight: 0.05,
        description: 'Recovers gracefully from failures'
      }
    }.freeze

    # Stricter tier expectations
    DIFFICULTY_TIERS = {
      tier_1: { name: 'Basic', multiplier: 1.0, expected: 0.98 },
      tier_2: { name: 'Standard', multiplier: 1.5, expected: 0.90 },
      tier_3: { name: 'Advanced', multiplier: 2.0, expected: 0.70 },
      tier_4: { name: 'Expert', multiplier: 3.0, expected: 0.40 },
      tier_5: { name: 'Nightmare', multiplier: 5.0, expected: 0.15 }
    }.freeze

    CATEGORIES = {
      # === FACTORY TESTS ===
      platform_factory: 'Platform Factory (Module Building)',
      tool_factory: 'Tool Factory (Custom Tools)',
      agent_factory: 'Agent Factory (Agent Creation)',
      integration_factory: 'Integration Factory (External APIs)',
      orchestration: 'Cross-Factory Orchestration',
      
      # === VERIFICATION LEVELS ===
      exact_output: 'Exact Output Verification',
      side_effects: 'Side Effect Verification',
      
      # === STRESS TESTS ===
      adversarial: 'Adversarial Prompts',
      multi_step: 'Multi-Step Workflows',
      failure_recovery: 'Failure & Recovery',
      memory_context: 'Memory & Context'
    }.freeze

    # Verification types for the eval harness
    VERIFICATION_TYPES = {
      # L1: Weak - just check tool was called
      tool_called: {
        level: 1,
        description: 'Verify expected tool was invoked'
      },
      
      # L2: Medium - check tool args
      tool_args_match: {
        level: 2,
        description: 'Verify tool called with correct arguments'
      },
      
      # L3: Strong - check side effects
      artifact_created: {
        level: 3,
        description: 'Verify expected artifact exists in database',
        async_aware: true
      },
      
      # L4: Exact - check output matches exactly
      exact_match: {
        level: 4,
        description: 'Verify output matches ground truth exactly'
      },
      
      # L5: Integration - full workflow verification
      workflow_complete: {
        level: 5,
        description: 'Verify entire workflow completed with all artifacts'
      }
    }.freeze

    # ============================================
    # TIER 1: BASIC - Should be near-perfect
    # Expectation: 98%+ success rate
    # ============================================
    TIER_1_TASKS = [
      {
        id: 'b1_data_001',
        tier: :tier_1,
        category: :exact_output,
        name: 'Count with exact format',
        setup: -> (runner) { runner.ensure_contacts(10) },
        request: 'How many contacts do I have? Reply with just the number.',
        verification: :exact_match,
        ground_truth: -> (runner) { Contact.where(entity: runner.entity).count.to_s },
        extract_answer: -> (response) { response.scan(/\d+/).first },
        rubric: { correctness: 'Must return exact count as a number' },
        max_latency_ms: 10_000,
        max_tool_calls: 2
      },
      {
        id: 'b1_canvas_001',
        tier: :tier_1,
        category: :side_effects,
        name: 'Load dashboard canvas',
        request: 'Show me my dashboard',
        verification: :canvas_loaded,
        expected_canvas: 'dashboard',
        max_latency_ms: 10_000
      },
      {
        id: 'b1_canvas_002',
        tier: :tier_1,
        category: :side_effects,
        name: 'Load landing pages canvas',
        request: 'Show me my landing pages',
        verification: :canvas_loaded,
        expected_canvas: 'landing_page_viewer',
        max_latency_ms: 10_000
      },
      {
        id: 'b1_create_001',
        tier: :tier_1,
        category: :side_effects,
        name: 'Create contact and verify',
        request: 'Create a contact named "BOB Test" with email "bob.test@benchmark.com"',
        verification: :artifact_created,
        artifact_type: Contact,
        artifact_query: -> (entity) { Contact.find_by(entity: entity, email: 'bob.test@benchmark.com') },
        expected_fields: { first_name: 'BOB', email: 'bob.test@benchmark.com' },
        cleanup: -> (runner) { Contact.where(email: 'bob.test@benchmark.com').destroy_all },
        max_latency_ms: 15_000
      }
      # NEW: Create email template and verify
      {
        id: 'b1_template_001',
        tier: :tier_1,
        category: :side_effects,
        name: 'Create email template',
        request: 'Create an email template called "Test Welcome" with subject "Welcome!" and body "<h1>Hello!</h1><p>Welcome aboard.</p>"',
        verification: :artifact_created,
        artifact_type: EmailTemplate,
        artifact_query: -> (entity) { EmailTemplate.find_by(entity: entity, name: 'Test Welcome') },
        expected_fields: { name: 'Test Welcome', subject: 'Welcome!' },
        cleanup: -> (runner) { EmailTemplate.where(entity: runner.entity, name: 'Test Welcome').destroy_all },
        max_latency_ms: 15_000
      },
      # NEW: Delete a contact
      {
        id: 'b1_delete_001',
        tier: :tier_1,
        category: :side_effects,
        name: 'Delete a contact',
        setup: -> (runner) {
          Contact.where(entity: runner.entity, email: 'delete.me@benchmark.com').destroy_all
          Contact.create!(entity: runner.entity, user: runner.user, first_name: 'Delete', last_name: 'Me', email: 'delete.me@benchmark.com', status: 'active')
        },
        request: -> (runner) {
          contact = Contact.find_by(entity: runner.entity, email: 'delete.me@benchmark.com')
          "Delete the contact with ID #{contact.id}"
        },
        verification: :workflow_complete,
        workflow_steps: [
          {
            description: 'Contact deleted',
            tool: 'platform_execute',
            check: -> (runner) { !Contact.exists?(entity: runner.entity, email: 'delete.me@benchmark.com') }
          }
        ],
        max_latency_ms: 15_000
      }
    ].freeze

    # ============================================
    # TIER 2: STANDARD - Multi-step, verified
    # Expectation: 90%+ success rate
    # ============================================
    TIER_2_TASKS = [
      {
        id: 'b2_multi_001',
        tier: :tier_2,
        category: :multi_step,
        name: 'Create and update workflow',
        # User-friendly language - the app should auto-map "qualified" to lifecycle_stage: mql
        request: 'Create a contact named "Update Test" with email "update@test.com", then mark them as qualified',
        verification: :workflow_complete,
        workflow_steps: [
          { 
            description: 'Contact created',
            tool: 'create_object', 
            check: -> (runner) { Contact.exists?(entity: runner.entity, email: 'update@test.com') } 
          },
          { 
            description: 'Contact marked as qualified (lifecycle_stage = mql)',
            tool: 'update_object', 
            # App should auto-map "qualified" → lifecycle_stage: mql
            check: -> (runner) { 
              contact = Contact.find_by(entity: runner.entity, email: 'update@test.com')
              contact&.lifecycle_stage == 'mql' || contact&.lifecycle_stage&.include?('qual')
            } 
          }
        ],
        cleanup: -> (runner) { Contact.where(email: 'update@test.com').destroy_all },
        max_latency_ms: 30_000
      },
      {
        id: 'b2_query_001',
        tier: :tier_2,
        category: :exact_output,
        name: 'Filtered count with breakdown',
        setup: -> (runner) { 
          # Clean up ALL contacts for this entity first to ensure predictable counts
          Contact.where(entity: runner.entity).destroy_all
          # Create exactly 10 leads and 5 MQL (qualified) contacts
          10.times { |i| runner.create_test_contact(lifecycle_stage: 'lead', email: "benchmark_lead_#{i}@test.com") }
          5.times { |i| runner.create_test_contact(lifecycle_stage: 'mql', email: "benchmark_mql_#{i}@test.com") }
        },
        request: 'How many leads vs qualified contacts do I have? Format: "Leads: X, Qualified: Y"',
        verification: :exact_match,
        ground_truth: -> (runner) {
          # Ground truth matches what AI will see (all contacts in entity)
          leads = Contact.where(entity: runner.entity, lifecycle_stage: 'lead').count
          qualified = Contact.where(entity: runner.entity, lifecycle_stage: 'mql').count
          "Leads: #{leads}, Qualified: #{qualified}"
        },
        cleanup: -> (runner) {
          Contact.where(entity: runner.entity).where("email LIKE 'benchmark%@test.com'").destroy_all
        },
        extract_answer: -> (response) {
          leads = response.scan(/leads?[:\s]+(\d+)/i).flatten.first
          qualified = response.scan(/qualified[:\s]+(\d+)/i).flatten.first
          "Leads: #{leads}, Qualified: #{qualified}" if leads && qualified
        },
        max_latency_ms: 15_000
      },
      # NEW: Create automation rule
      {
        id: 'b2_automation_001',
        tier: :tier_2,
        category: :side_effects,
        name: 'Create automation rule',
        setup: -> (runner) {
          EmailTemplate.create!(entity: runner.entity, user: runner.user, name: 'BOB Automation Template', subject: 'Welcome', body: '<p>Hi!</p>')
        },
        request: -> (runner) {
          template = EmailTemplate.find_by(entity: runner.entity, name: 'BOB Automation Template')
          "Create an automation called 'Welcome Flow' that sends email template #{template.id} when a new contact is created"
        },
        verification: :artifact_created,
        artifact_type: AutomationCode,
        artifact_query: -> (entity) { AutomationCode.find_by(entity: entity, name: 'Welcome Flow') },
        expected_fields: { trigger_type: 'record_created', status: 'active' },
        cleanup: -> (runner) {
          AutomationCode.where(entity: runner.entity, name: 'Welcome Flow').destroy_all
          EmailTemplate.where(entity: runner.entity, name: 'BOB Automation Template').destroy_all
        },
        max_latency_ms: 20_000
      },
      # NEW: Add custom field to Contact
      {
        id: 'b2_schema_001',
        tier: :tier_2,
        category: :side_effects,
        name: 'Add custom field to Contact',
        request: 'Add a custom field called "industry" of type "string" to contacts',
        verification: :artifact_created,
        artifact_type: CustomFieldDefinition,
        artifact_query: -> (entity) { CustomFieldDefinition.find_by(entity: entity, model_type: 'Contact', field_name: 'industry') },
        expected_fields: { field_type: 'string', active: true },
        cleanup: -> (runner) {
          CustomFieldDefinition.where(entity: runner.entity, model_type: 'Contact', field_name: 'industry').destroy_all
        },
        max_latency_ms: 15_000
      }
    ].freeze

    # ============================================
    # TIER 3: ADVANCED - Factory Tests
    # Expectation: 70%+ success rate
    # ============================================
    TIER_3_TASKS = [
      # NEW: Full welcome email automation flow (multi-turn)
      {
        id: 'b3_welcome_flow_001',
        tier: :tier_3,
        category: :multi_step,
        name: 'Full welcome email automation flow',
        conversation: [
          { role: 'user', content: 'Create an email template called "BOB Welcome" with subject "Welcome to our platform!" and body "<h1>Welcome!</h1><p>We are glad to have you.</p>"' },
          { role: 'user', content: 'Now create an automation that sends that template whenever a new contact is created. Call it "BOB Welcome Automation".' }
        ],
        verification: :workflow_complete,
        workflow_steps: [
          {
            description: 'Email template created',
            tool: 'platform_create',
            check: -> (runner) { EmailTemplate.exists?(entity: runner.entity, name: 'BOB Welcome') }
          },
          {
            description: 'Automation created and active',
            tool: 'platform_create',
            check: -> (runner) {
              AutomationCode.exists?(entity: runner.entity, name: 'BOB Welcome Automation', status: 'active')
            }
          }
        ],
        cleanup: -> (runner) {
          AutomationCode.where(entity: runner.entity).where("name LIKE 'BOB Welcome%'").destroy_all
          EmailTemplate.where(entity: runner.entity, name: 'BOB Welcome').destroy_all
        },
        max_latency_ms: 60_000
      },
      # PLATFORM FACTORY TEST
      # Tests that the AI can use request_module or start_module_design to begin module creation
      # Note: Full module generation is async and can take several minutes
      {
        id: 'b3_platform_001',
        tier: :tier_3,
        category: :platform_factory,
        name: 'Create custom module end-to-end',
        setup: -> (runner) {
          # Cancel any blocking active design sessions
          ModuleDesignSession.where(entity: runner.entity)
                             .where(status: ['gathering_requirements', 'awaiting_feedback', 'refining'])
                             .update_all(status: 'cancelled')
          # Clean up any existing Task Tracker sessions/modules (order matters for FK!)
          # First nullify the app_module reference in design sessions
          ModuleDesignSession.where(entity: runner.entity)
                             .where('module_name ILIKE ?', '%task%')
                             .update_all(app_module_id: nil)
          # Then delete the modules
          AppModule.where(entity: runner.entity).where('name ILIKE ?', '%task%').destroy_all
        },
        request: 'Build me a "Task Tracker" module with these fields: title (string), due_date (date), priority (low/medium/high), completed (boolean). Start building it immediately.',
        verification: :workflow_complete,
        expected_tools: ['request_module', 'start_module_design', 'start_app_design'],  # Any of these
        workflow_steps: [
          { 
            description: 'Module creation initiated',
            check: -> (runner) { 
              # Either a design session OR an app module should be created
              ModuleDesignSession.where(entity: runner.entity)
                                 .where('module_name ILIKE ?', '%task%')
                                 .where('created_at > ?', 5.minutes.ago).exists? ||
              AppModule.where(entity: runner.entity)
                       .where('name ILIKE ?', '%task%')
                       .where('created_at > ?', 5.minutes.ago).exists?
            }
          }
        ],
        async_timeout: 120,  # Module design via Platform Factory
        cleanup: -> (runner) { 
          # Nullify FK references first, then delete
          ModuleDesignSession.where(entity: runner.entity)
                             .where('module_name ILIKE ?', '%task%')
                             .update_all(app_module_id: nil)
          ModuleDesignSession.where(entity: runner.entity)
                             .where('module_name ILIKE ?', '%task%')
                             .destroy_all
          AppModule.where(entity: runner.entity).where('name ILIKE ?', '%task%').destroy_all
        },
        max_latency_ms: 60_000
      },
      
      # INTEGRATION FACTORY TEST
      {
        id: 'b3_integration_001',
        tier: :tier_3,
        category: :integration_factory,
        name: 'Create and test REST integration',
        setup: -> (runner) {
          # Clean ALL custom integrations for this entity to avoid hitting the 5-integration limit
          Integration.where(entity: runner.entity).destroy_all
          Rails.logger.info "[BOB] Cleared all integrations for benchmark entity"
        },
        request: <<~REQUEST.strip,
          Create a new REST API integration for HTTPBin (https://httpbin.org).
          
          It's a public API that doesn't require authentication.
          Name it "HTTPBin Test API" and test it to make sure it works.
        REQUEST
        verification: :workflow_complete,
        workflow_steps: [
          {
            description: 'Integration created',
            check: -> (runner) {
              Integration.where(entity: runner.entity)
                         .where('name ILIKE ? OR api_base_url ILIKE ?', '%httpbin%', '%httpbin%')
                         .where('created_at > ?', 5.minutes.ago).exists?
            }
          },
          {
            description: 'Integration tested successfully',
            check: -> (runner) {
              integration = Integration.where(entity: runner.entity)
                                        .where('name ILIKE ? OR api_base_url ILIKE ?', '%httpbin%', '%httpbin%')
                                        .first
              return false unless integration
              
              # Check if integration is verified OR has a connection with a successful log
              return true if integration.is_verified?
              
              # Check logs through connections
              connection = integration.connections.first
              return false unless connection
              
              # A successful log has a 2xx response status
              IntegrationLog.where(connection: connection)
                            .where('response_status >= 200 AND response_status < 300')
                            .exists?
            }
          }
        ],
        cleanup: -> (runner) {
          # Log what we're about to delete
          integrations = Integration.where(entity: runner.entity)
                                    .where('name ILIKE ? OR api_base_url ILIKE ?', '%httpbin%', '%httpbin%')
          Rails.logger.info "[BOB] Cleanup: Found #{integrations.count} HTTPBin integrations for entity #{runner.entity.id}"
          integrations.each { |i| Rails.logger.info "[BOB]   - #{i.name} (is_verified=#{i.is_verified}, connections=#{i.connections.count})" }
          integrations.destroy_all
        },
        async_timeout: 120,  # Integration creation via agent delegation
        max_latency_ms: 180_000
      }
    ].freeze

    # ============================================
    # TIER 4: EXPERT - Multi-Factory Coordination
    # Expectation: 40%+ success rate
    # ============================================
    TIER_4_TASKS = [
      # AGENT FACTORY TEST
      # Requires Solid Queue running: bundle exec rake solid_queue:start
      {
        id: 'b4_agent_001',
        tier: :tier_4,
        category: :agent_factory,
        name: 'Create landing page via agent delegation',
        request: <<~REQUEST.strip,
          Create a landing page for a summer sale. Here are ALL the details needed - proceed directly without asking questions:
          
          - Title: "Summer Savings 2024"
          - Headline: "Beat the Heat with 25% Off Everything!"
          - Subheadline: "Limited time summer sale - don't miss out"
          - Primary CTA: "Shop Now" (button)
          - Business: Benchmark Test Store
          - Industry: Retail/E-commerce
          - Color scheme: Bright summer colors (orange, yellow, blue)
          - Key selling points: 25% off all items, Free shipping over $50, Easy returns
          
          Generate the page immediately using these specifications.
        REQUEST
        verification: :artifact_created,
        artifact_type: LandingPage,
        artifact_query: -> (entity) { 
          LandingPage.where(entity: entity)
                     .where('title ILIKE ? OR title ILIKE ?', '%summer%', '%savings%')
                     .where('created_at > ?', 5.minutes.ago)
                     .first
        },
        async_timeout: 180,  # Agent delegation can take a while
        cleanup: -> (runner) {
          LandingPage.where(entity: runner.entity)
                     .where('title ILIKE ? OR title ILIKE ?', '%summer%', '%savings%')
                     .destroy_all
        },
        max_latency_ms: 300_000  # 5 minutes for full agent execution
      },
      
      # TOOL FACTORY TEST  
      {
        id: 'b4_tool_001',
        tier: :tier_4,
        category: :tool_factory,
        name: 'Create custom tool and execute it',
        request: 'Create a tool called "calculate_discount" that takes a price and discount_percent and returns the discounted price. Then use it to calculate 20% off $100.',
        verification: :workflow_complete,
        workflow_steps: [
          {
            description: 'Tool created',
            check: -> (runner) {
              ToolDefinition.where(entity: runner.entity).where('name ILIKE ?', '%discount%').exists?
            }
          },
          {
            description: 'Tool executed with correct result',
            check: -> (runner) {
              # Check if the response or agent execution output contains 80 (which is 100 - 20%)
              return true if runner.last_response.to_s.include?('80')
              
              # Also check recent tool_builder executions for the result
              agent = AgentPlugin.find_by(slug: 'tool_builder')
              if agent
                recent_exec = AgentPluginExecution.where(agent_plugin: agent)
                                                  .where('created_at > ?', 5.minutes.ago)
                                                  .order(created_at: :desc)
                                                  .first
                return recent_exec&.output_result.to_s.include?('80')
              end
              false
            }
          }
        ],
        cleanup: -> (runner) {
          tools = ToolDefinition.where(entity: runner.entity).where('name ILIKE ?', '%discount%')
          # Delete related records first to avoid FK violations
          ToolUsageMetric.where(tool_definition: tools).delete_all if defined?(ToolUsageMetric)
          tools.destroy_all
        },
        async_timeout: 60,  # Wait for async tool creation via agent delegation
        max_latency_ms: 120_000
      },
      
      # CROSS-FACTORY ORCHESTRATION
      {
        id: 'b4_orchestration_001',
        tier: :tier_4,
        category: :orchestration,
        name: 'Plan complex multi-agent workflow',
        request: 'I need to build a complete customer onboarding system. Create a plan that includes: 1) A welcome email template, 2) A landing page for new customers, 3) A contact tracking module',
        verification: :workflow_complete,
        workflow_steps: [
          {
            description: 'Plan created with multiple steps',
            check: -> (runner) {
              plan = ExecutionPlan.where(entity: runner.entity).where('created_at > ?', 2.minutes.ago).first
              plan.present? && (plan.total_steps || 0) >= 2
            }
          }
        ],
        max_latency_ms: 60_000
      }
    ].freeze

    # ============================================
    # TIER 5: NIGHTMARE - Should be brutally hard
    # Expectation: 15%+ success rate
    # ============================================
    TIER_5_TASKS = [
      # FULL ORCHESTRATION: All factories together
      {
        id: 'b5_full_001',
        tier: :tier_5,
        category: :orchestration,
        name: 'Build complete app with all components',
        request: <<~REQUEST.strip,
          Build me a complete "Event Management" app with the following components. Proceed autonomously without asking questions - use sensible defaults.
          
          1. An "Events" module with fields: name (string), date (datetime), location (string), capacity (integer), ticket_price (decimal)
          
          2. A landing page for event registration with:
             - Title: "Event Registration"
             - Modern, professional design with blue color scheme
             - Headline: "Register for Upcoming Events"
             - CTA button: "Register Now"
             - Include event name, date, location fields
          
          3. An integration with HTTPBin API (https://httpbin.org) for testing HTTP requests
          
          4. A scheduled task to send reminders 1 day before events
        REQUEST
        verification: :workflow_complete,
        workflow_steps: [
          { description: 'App or module created', check: -> (r) { 
            # Use 10 minutes to account for async polling time (up to 5 min)
            AppModule.where(entity: r.entity).where('name ILIKE ?', '%event%').where('created_at > ?', 10.minutes.ago).exists? ||
            App.where(entity: r.entity).where('name ILIKE ?', '%event%').where('created_at > ?', 10.minutes.ago).exists?
          }},
          { description: 'Landing page created', check: -> (r) {
            LandingPage.where(entity: r.entity).where('created_at > ?', 10.minutes.ago).exists?
          }},
          { description: 'Integration configured', check: -> (r) {
            Integration.where(entity: r.entity).where('created_at > ?', 10.minutes.ago).exists?
          }}
        ],
        cleanup: -> (runner) {
          AppModule.where(entity: runner.entity).where('name ILIKE ?', '%event%').destroy_all
          App.where(entity: runner.entity).where('name ILIKE ?', '%event%').destroy_all
          LandingPage.where(entity: runner.entity).where('created_at > ?', 10.minutes.ago).destroy_all
        },
        async_timeout: 300,  # 5 minutes
        max_latency_ms: 600_000  # 10 minutes
      },
      
      # ADVERSARIAL: Conflicting instructions
      {
        id: 'b5_adversarial_001',
        tier: :tier_5,
        category: :adversarial,
        name: 'Handle rapidly changing requirements',
        conversation: [
          { role: 'user', content: 'Create a contact named John Smith with email john@test.com' },
          { role: 'assistant', content: nil },
          { role: 'user', content: 'Actually make it Jane Smith instead' },
          { role: 'assistant', content: nil },
          { role: 'user', content: 'Change the email to jane@company.com and set status to VIP' }
        ],
        verification: :artifact_created,
        artifact_type: Contact,
        artifact_query: -> (entity) {
          # Find contact that was updated to jane@company.com
          Contact.find_by(entity: entity, email: 'jane@company.com')
        },
        # Only verify the email - the name changes are part of the adversarial challenge
        expected_fields: { email: 'jane@company.com' },
        cleanup: -> (runner) {
          Contact.where(entity: runner.entity, email: ['john@test.com', 'jane@company.com']).destroy_all
        },
        max_latency_ms: 60_000
      },
      
      # EXACT OUTPUT: Precise formatting
      {
        id: 'b5_exact_001',
        tier: :tier_5,
        category: :exact_output,
        name: 'Generate exactly formatted report',
        setup: -> (runner) {
          # CRITICAL: Delete ALL records for this entity to get exact counts
          Contact.where(entity: runner.entity).destroy_all
          Campaign.where(entity: runner.entity).destroy_all
          LandingPage.where(entity: runner.entity).destroy_all
          
          # Now create EXACTLY the counts we want
          25.times do |i|
            Contact.create!(
              entity: runner.entity,
              user: runner.user,
              first_name: "Exact",
              last_name: "Contact#{i}",
              email: "exact_#{i}@benchmark.test",
              status: 'active',
              lifecycle_stage: 'lead'
            )
          end
          
          5.times do |i|
            Campaign.create!(
              entity: runner.entity,
              user: runner.user,
              name: "Exact Campaign #{i}",
              status: 'draft'
            )
          end
          
          3.times do |i|
            LandingPage.create!(
              entity: runner.entity,
              user: runner.user,
              title: "Exact Page #{i}",
              slug: "exact-page-#{i}-#{SecureRandom.hex(4)}",
              status: 'draft'
            )
          end
          
          # Verify setup worked
          actual_contacts = Contact.where(entity: runner.entity).count
          actual_campaigns = Campaign.where(entity: runner.entity).count
          actual_pages = LandingPage.where(entity: runner.entity).count
          Rails.logger.info "[BOB] b5_exact_001 setup complete: Contacts=#{actual_contacts}, Campaigns=#{actual_campaigns}, Pages=#{actual_pages}"
        },
        request: 'Give me a summary in this EXACT format: "Contacts: [N], Campaigns: [N], Pages: [N]" - replace [N] with actual counts from the database, nothing else',
        verification: :exact_match,
        ground_truth: -> (runner) {
          contacts = Contact.where(entity: runner.entity).count
          campaigns = Campaign.where(entity: runner.entity).count  
          pages = LandingPage.where(entity: runner.entity).count
          Rails.logger.info "[BOB] b5_exact_001 ground_truth: Contacts: #{contacts}, Campaigns: #{campaigns}, Pages: #{pages}"
          "Contacts: #{contacts}, Campaigns: #{campaigns}, Pages: #{pages}"
        },
        extract_answer: -> (response) {
          match = response.match(/Contacts:\s*(\d+),?\s*Campaigns:\s*(\d+),?\s*Pages:\s*(\d+)/i)
          "Contacts: #{match[1]}, Campaigns: #{match[2]}, Pages: #{match[3]}" if match
        },
        cleanup: -> (runner) {
          Contact.where(entity: runner.entity).where("email LIKE 'exact_%@benchmark.test'").destroy_all
          Campaign.where(entity: runner.entity).where("name LIKE 'Exact Campaign%'").destroy_all
          LandingPage.where(entity: runner.entity).where("title LIKE 'Exact Page%'").destroy_all
        },
        max_latency_ms: 15_000
      },
      
      # FAILURE RECOVERY: Handle broken state
      {
        id: 'b5_recovery_001',
        tier: :tier_5,
        category: :failure_recovery,
        name: 'Recover from failed plan step',
        setup: -> (runner) { runner.create_failing_plan_step },
        request: 'My plan has a failed step. Diagnose the issue and suggest how to fix it.',
        verification: :tool_args_match,
        expected_tools: ['get_plan_status'],
        expected_behavior: :identifies_failure,
        behavior_check: -> (response) {
          response.downcase.include?('fail') && 
          (response.downcase.include?('retry') || response.downcase.include?('skip') || response.downcase.include?('fix'))
        },
        max_latency_ms: 20_000
      },
      
      # MEMORY: Multi-turn with callback
      {
        id: 'b5_memory_001',
        tier: :tier_5,
        category: :memory_context,
        name: '5-turn conversation with context recall',
        conversation: [
          { role: 'user', content: 'Remember this: the secret code is ALPHA-7' },
          { role: 'assistant', content: nil },
          { role: 'user', content: 'Create a contact named Test User' },
          { role: 'assistant', content: nil },
          { role: 'user', content: 'What landing pages do I have?' },
          { role: 'assistant', content: nil },
          { role: 'user', content: 'List my campaigns' },
          { role: 'assistant', content: nil },
          { role: 'user', content: 'What was the secret code I told you earlier?' }
        ],
        verification: :exact_match,
        ground_truth: -> (runner) { 'ALPHA-7' },
        extract_answer: -> (response) {
          match = response.match(/ALPHA-7/i)
          match[0] if match
        },
        max_latency_ms: 120_000
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

      def factory_tasks
        all_tasks.select { |t| t[:category].to_s.include?('factory') || t[:category] == :orchestration }
      end

      def task(id)
        all_tasks.find { |t| t[:id] == id }
      end

      def difficulty_breakdown
        DIFFICULTY_TIERS.keys.map { |tier| [tier, tasks_by_tier(tier).count] }.to_h
      end

      def category_breakdown
        all_tasks.group_by { |t| t[:category] }.transform_values(&:count)
      end

      def total_tasks
        all_tasks.count
      end

      def verification_coverage
        all_tasks.group_by { |t| t[:verification] }.transform_values(&:count)
      end

      def expected_score_range
        {
          baseline_system: 20..40,      # Basic LLM wrapper
          good_system: 40..60,          # Well-configured assistant  
          excellent_system: 60..75,     # Full agentic system
          expert_system: 75..90,        # Production-ready
          world_class: 90..100          # Near-perfect (very hard to achieve)
        }
      end
    end
  end
end

