# frozen_string_literal: true

module Benchmarks
  # ============================================
  # Business Operations Benchmark (BOB) v2.0
  # "MMLU for Running a Business" - HARD MODE
  # 
  # Redesigned based on v1.0 results:
  # - Reduced non-grounded tasks (pure LLM) to 2 per category
  # - Expanded tool variety (60+ tools available)
  # - Added agent delegation tests (landing page, email, etc.)
  # - Added multimodal tests (PDF reading, document RAG)
  # - Added complex orchestration (integration + tools + agent)
  # 
  # Total: ~75 tasks (down from 165)
  # Focus: Tool usage, agent collaboration, asset creation
  # ============================================
  class BusinessBenchmarkV2
    CATEGORIES = {
      # Minimal pure-LLM tasks (2 each = 20 total)
      strategy: 'Strategy & Planning',
      finance: 'Finance & Cash Flow',
      sales: 'Sales & CRM',
      marketing: 'Marketing & Growth',
      operations: 'Operations & Process',
      hr: 'HR & People Ops',
      customer_success: 'Customer Support & Success',
      analytics: 'Analytics & Decision Support',
      admin: 'Admin, Scheduling & Communication',
      compliance: 'Compliance, Risk & Vendor Management',
      
      # Heavy tool usage categories
      grounded: 'Tool-Based Tasks (Require External Data)',
      multimodal: 'Multimodal (Documents, PDFs, Images)',
      agent_delegation: 'Agent Delegation (Specialist Handoff)',
      creation: 'Asset Creation (Integrations, Tools, Pages)',
      orchestration: 'Complex Orchestration (Multi-Step Workflows)',
      extreme: 'Extreme Challenges (Multi-Agent, Multi-Asset)'
    }.freeze

    # Available tools for reference (used in task design)
    TOOL_CATEGORIES = {
      data_access: %w[get_data get_schema explain_query],
      web_research: %w[web_search],
      documents: %w[list_documents read_document query_document_content query_rag_store create_rag_store],
      integrations: %w[list_connections list_operations invoke_operation execute_integration create_integration_foundation configure_integration_auth add_integration_operations test_integration_auth],
      agents: %w[list_available_agents delegate_to_agent invoke_agent_plugin ask_agent_for_help],
      creation: %w[create_agent_plugin create_tool_definition generate_landing_page create_object update_object],
      analytics: %w[query_metric list_metrics create_dynamic_visualization aggregate_artifact_data],
      pipeline: %w[manage_pipeline],
      tasks: %w[manage_task_list],
      billing: %w[get_billing_info get_token_usage get_my_ai_usage view_invoices],
      history: %w[search_history retrieve_history]
    }.freeze

    # Available agents for delegation
    AVAILABLE_AGENTS = %w[
      ai_landing_page_creator
      email_sequence_architect
      integration_architect
      sales_email_generator
      content_quality_analyzer
      campaign_optimizer
      tool_builder
      web_research_specialist
      swot_analysis_agent
      roi_analysis_agent
      agent_architect
    ].freeze

    TASKS = [
      # ============================================
      # PURE LLM TASKS (2 per category = 20 total)
      # These are just sanity checks, not the focus
      # ============================================
      
      # Strategy (2)
      {
        id: 'llm_strategy_001',
        category: :strategy,
        name: 'SWOT snapshot',
        scenario: '10-year-old manufacturing SMB facing cheaper overseas competitors.',
        request: 'Scout, draft a quick SWOT analysis for a mid-sized local manufacturer competing against offshore competitors.',
        rubric: ['Structured SWOT format', 'Business-relevant points', 'Specific not generic'],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'llm_strategy_002',
        category: :strategy,
        name: 'Prioritize initiatives',
        scenario: 'Owner has 5 possible initiatives and limited bandwidth.',
        request: 'Help me prioritize: 1) Launch mobile app, 2) Expand to Canada, 3) Add enterprise tier, 4) Build partner program, 5) Add AI features. Use impact/effort framework.',
        rubric: ['Impact/effort matrix', 'Clear top 2-3 recommendation', 'Brief rationale'],
        requires_tools: false,
        difficulty: :medium
      },

      # Finance (2)
      {
        id: 'llm_finance_001',
        category: :finance,
        name: 'Breakeven analysis',
        scenario: 'Coffee shop considering adding a food menu.',
        request: 'Monthly rent $3k, labor $5k, food costs 40% of revenue. What monthly food revenue do I need to break even on the food operation?',
        rubric: ['Correct math', 'Shows work', 'Clear answer'],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'llm_finance_002',
        category: :finance,
        name: 'Unit economics',
        scenario: 'SaaS company evaluating customer acquisition.',
        request: 'CAC is $500, monthly subscription $50, average customer stays 18 months, gross margin 80%. Calculate LTV and LTV:CAC ratio. Is this healthy?',
        rubric: ['Correct LTV calculation', 'Correct ratio', 'Interpretation of health'],
        requires_tools: false,
        difficulty: :medium
      },

      # Sales (2)
      {
        id: 'llm_sales_001',
        category: :sales,
        name: 'Objection handling',
        scenario: 'B2B software sales.',
        request: 'Write 3 responses to: "Your competitor is 30% cheaper."',
        rubric: ['3 distinct approaches', 'Value-focused not defensive', 'Professional tone'],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'llm_sales_002',
        category: :sales,
        name: 'Discovery questions',
        scenario: 'Selling project management software.',
        request: 'Create 5 discovery questions to understand a prospect\'s pain points around project management.',
        rubric: ['Open-ended questions', 'Pain-focused', 'Not leading'],
        requires_tools: false,
        difficulty: :easy
      },

      # Marketing (2)
      {
        id: 'llm_marketing_001',
        category: :marketing,
        name: 'Value proposition',
        scenario: 'AI-powered expense tracking app.',
        request: 'Write a compelling value proposition in 2 sentences for an AI expense tracker that auto-categorizes receipts.',
        rubric: ['Clear benefit', 'Specific differentiator', 'Concise'],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'llm_marketing_002',
        category: :marketing,
        name: 'Email subject lines',
        scenario: 'Promoting a webinar.',
        request: 'Write 5 email subject lines for a webinar about "Scaling Your Agency to $1M ARR".',
        rubric: ['5 distinct options', 'Compelling/curiosity-driven', 'Appropriate length'],
        requires_tools: false,
        difficulty: :easy
      },

      # Operations (2)
      {
        id: 'llm_operations_001',
        category: :operations,
        name: 'SOP outline',
        scenario: 'Customer onboarding process.',
        request: 'Create an outline for an SOP on onboarding a new enterprise customer.',
        rubric: ['Clear steps', 'Roles mentioned', 'Checkpoints included'],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'llm_operations_002',
        category: :operations,
        name: 'Vendor evaluation',
        scenario: 'Choosing a CRM.',
        request: 'Create a simple scoring matrix to evaluate 3 CRM vendors. Include 5 criteria.',
        rubric: ['5 relevant criteria', 'Scoring method', 'Weighting suggested'],
        requires_tools: false,
        difficulty: :medium
      },

      # HR (2)
      {
        id: 'llm_hr_001',
        category: :hr,
        name: 'Interview questions',
        scenario: 'Hiring a customer success manager.',
        request: 'Create 5 behavioral interview questions for a Customer Success Manager role.',
        rubric: ['Behavioral format (STAR)', 'Role-relevant', 'Varied competencies'],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'llm_hr_002',
        category: :hr,
        name: 'Performance review',
        scenario: 'Quarterly review template.',
        request: 'Create a simple quarterly performance review template with 4 sections.',
        rubric: ['4 distinct sections', 'Includes goals', 'Includes feedback areas'],
        requires_tools: false,
        difficulty: :easy
      },

      # Customer Success (2)
      {
        id: 'llm_cs_001',
        category: :customer_success,
        name: 'Churn save script',
        scenario: 'Customer wants to cancel.',
        request: 'Write a script for a call with a customer who wants to cancel due to "not using it enough".',
        rubric: ['Empathetic opening', 'Discovery of real issue', 'Value reminder', 'Save offer'],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'llm_cs_002',
        category: :customer_success,
        name: 'NPS follow-up',
        scenario: 'Customer gave NPS score of 6.',
        request: 'Write a follow-up email to a customer who gave an NPS score of 6 (passive).',
        rubric: ['Thanks for feedback', 'Asks what would make it a 9', 'Offers help'],
        requires_tools: false,
        difficulty: :easy
      },

      # Analytics (2)
      {
        id: 'llm_analytics_001',
        category: :analytics,
        name: 'KPI selection',
        scenario: 'E-commerce business.',
        request: 'Recommend 5 KPIs for an e-commerce business and explain why each matters.',
        rubric: ['5 relevant KPIs', 'Brief explanation each', 'Mix of leading/lagging'],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'llm_analytics_002',
        category: :analytics,
        name: 'A/B test interpretation',
        scenario: 'Testing checkout button color.',
        request: 'Variant A: 1000 visitors, 45 conversions. Variant B: 1000 visitors, 52 conversions. Is this statistically significant? What do you recommend?',
        rubric: ['Calculates conversion rates', 'Addresses significance', 'Clear recommendation'],
        requires_tools: false,
        difficulty: :medium
      },

      # Admin (2)
      {
        id: 'llm_admin_001',
        category: :admin,
        name: 'Meeting agenda',
        scenario: 'Weekly team standup.',
        request: 'Create a 30-minute weekly team standup agenda for a 6-person team.',
        rubric: ['Time-boxed sections', 'Covers blockers', 'Action-oriented'],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'llm_admin_002',
        category: :admin,
        name: 'Vendor email',
        scenario: 'Negotiating contract renewal.',
        request: 'Write an email to a vendor asking for a 15% discount on renewal, citing budget constraints.',
        rubric: ['Professional tone', 'Clear ask', 'Provides reasoning', 'Leaves room for negotiation'],
        requires_tools: false,
        difficulty: :easy
      },

      # Compliance (2)
      {
        id: 'llm_compliance_001',
        category: :compliance,
        name: 'Risk register',
        scenario: 'Small software company.',
        request: 'Create a simple risk register with 5 common risks for a small software company. Include likelihood, impact, and mitigation.',
        rubric: ['5 relevant risks', 'Likelihood/impact rated', 'Mitigation strategies'],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'llm_compliance_002',
        category: :compliance,
        name: 'Data policy',
        scenario: 'GDPR compliance.',
        request: 'Outline the key sections needed in a data privacy policy for GDPR compliance.',
        rubric: ['Key GDPR sections', 'Plain language', 'Actionable'],
        requires_tools: false,
        difficulty: :medium
      },

      # ============================================
      # TOOL-BASED TASKS (Require External Data)
      # Tests variety of tool usage
      # ============================================
      
      # Data Access Tools
      {
        id: 'tool_data_001',
        category: :grounded,
        name: 'Contact count and breakdown',
        scenario: 'Need to understand our contact database.',
        request: 'How many contacts do we have? Break down by source if possible.',
        rubric: ['Uses get_data tool', 'Returns actual count', 'Attempts breakdown'],
        requires_tools: true,
        expected_tools: ['get_data'],
        grounding_required: true,
        difficulty: :easy
      },
      {
        id: 'tool_data_002',
        category: :grounded,
        name: 'Database schema exploration',
        scenario: 'Developer wants to understand data model.',
        request: 'What data tables and fields are available in our system? Show me the schema.',
        rubric: ['Uses get_schema tool', 'Lists available models', 'Shows key fields'],
        requires_tools: true,
        expected_tools: ['get_schema'],
        grounding_required: true,
        difficulty: :easy
      },
      {
        id: 'tool_data_003',
        category: :grounded,
        name: 'Pipeline analysis',
        scenario: 'Sales manager needs pipeline overview.',
        request: 'Show me our current sales pipeline. What deals are in each stage?',
        rubric: ['Uses get_data or manage_pipeline', 'Shows stages', 'Shows deal values'],
        requires_tools: true,
        expected_tools: ['get_data', 'manage_pipeline'],
        grounding_required: true,
        difficulty: :medium
      },

      # Web Research Tools
      {
        id: 'tool_web_001',
        category: :grounded,
        name: 'Competitor research',
        scenario: 'Researching a competitor.',
        request: 'Research Salesforce\'s latest product announcements and pricing changes.',
        rubric: ['Uses web_search', 'Returns current info', 'Cites sources'],
        requires_tools: true,
        expected_tools: ['web_search'],
        grounding_required: true,
        difficulty: :medium
      },
      {
        id: 'tool_web_002',
        category: :grounded,
        name: 'Industry news',
        scenario: 'Staying current on AI trends.',
        request: 'What are the top 3 AI news stories from this week?',
        rubric: ['Uses web_search', 'Returns recent news', 'Multiple sources'],
        requires_tools: true,
        expected_tools: ['web_search'],
        grounding_required: true,
        difficulty: :easy
      },
      {
        id: 'tool_web_003',
        category: :grounded,
        name: 'Regulatory update',
        scenario: 'Compliance officer needs updates.',
        request: 'What are the latest GDPR enforcement actions or updates from the past month?',
        rubric: ['Uses web_search', 'Returns regulatory info', 'Recent timeframe'],
        requires_tools: true,
        expected_tools: ['web_search'],
        grounding_required: true,
        difficulty: :medium
      },

      # Integration Tools
      {
        id: 'tool_int_001',
        category: :grounded,
        name: 'List connected integrations',
        scenario: 'Admin wants to see what\'s connected.',
        request: 'What integrations are currently connected to our system?',
        rubric: ['Uses list_connections', 'Shows integration names', 'Shows status'],
        requires_tools: true,
        expected_tools: ['list_connections'],
        grounding_required: true,
        difficulty: :easy
      },
      {
        id: 'tool_int_002',
        category: :grounded,
        name: 'Integration capabilities',
        scenario: 'Exploring what an integration can do.',
        request: 'What operations are available for our Stripe integration?',
        rubric: ['Uses list_operations', 'Shows available endpoints', 'Describes capabilities'],
        requires_tools: true,
        expected_tools: ['list_operations'],
        grounding_required: true,
        difficulty: :medium
      },

      # Agent Discovery Tools
      {
        id: 'tool_agent_001',
        category: :grounded,
        name: 'Available agents',
        scenario: 'User wants to know what specialists are available.',
        request: 'What specialist agents are available to help me?',
        rubric: ['Uses list_available_agents', 'Lists agent names', 'Describes capabilities'],
        requires_tools: true,
        expected_tools: ['list_available_agents'],
        grounding_required: true,
        difficulty: :easy
      },

      # Analytics Tools
      {
        id: 'tool_analytics_001',
        category: :grounded,
        name: 'Token usage report',
        scenario: 'Admin checking AI costs.',
        request: 'How many AI tokens have we used this month? Show me the breakdown.',
        rubric: ['Uses get_token_usage or get_my_ai_usage', 'Shows token counts', 'Shows cost if available'],
        requires_tools: true,
        expected_tools: ['get_token_usage', 'get_my_ai_usage'],
        grounding_required: true,
        difficulty: :easy
      },
      {
        id: 'tool_analytics_002',
        category: :grounded,
        name: 'Billing information',
        scenario: 'User checking subscription.',
        request: 'What\'s my current billing status and subscription plan?',
        rubric: ['Uses get_billing_info', 'Shows plan details', 'Shows billing status'],
        requires_tools: true,
        expected_tools: ['get_billing_info'],
        grounding_required: true,
        difficulty: :easy
      },

      # History Tools
      {
        id: 'tool_history_001',
        category: :grounded,
        name: 'Conversation history',
        scenario: 'User wants to find a past conversation.',
        request: 'Search my conversation history for discussions about "landing pages".',
        rubric: ['Uses search_history', 'Returns relevant results', 'Shows context'],
        requires_tools: true,
        expected_tools: ['search_history'],
        grounding_required: true,
        difficulty: :medium
      },

      # ============================================
      # MULTIMODAL TASKS (Documents, PDFs)
      # Tests document reading and RAG
      # ============================================
      {
        id: 'mm_doc_001',
        category: :multimodal,
        name: 'List uploaded documents',
        scenario: 'User wants to see their documents.',
        request: 'What documents have been uploaded to my account?',
        rubric: ['Uses list_documents', 'Shows document names', 'Shows types/dates'],
        requires_tools: true,
        expected_tools: ['list_documents'],
        grounding_required: true,
        difficulty: :easy
      },
      {
        id: 'mm_doc_002',
        category: :multimodal,
        name: 'Read specific document',
        scenario: 'User wants to read a document.',
        request: 'Read the most recent document I uploaded and summarize its key points.',
        rubric: ['Uses list_documents then read_document', 'Extracts content', 'Provides summary'],
        requires_tools: true,
        expected_tools: ['list_documents', 'read_document'],
        grounding_required: true,
        difficulty: :medium
      },
      {
        id: 'mm_doc_003',
        category: :multimodal,
        name: 'Query document content',
        scenario: 'User searching for specific info in documents.',
        request: 'Search my documents for any mentions of "pricing" or "cost".',
        rubric: ['Uses query_document_content', 'Returns relevant excerpts', 'Shows source documents'],
        requires_tools: true,
        expected_tools: ['query_document_content'],
        grounding_required: true,
        difficulty: :medium
      },
      {
        id: 'mm_doc_004',
        category: :multimodal,
        name: 'Document-based analysis',
        scenario: 'User wants analysis of uploaded contract.',
        request: 'I uploaded a vendor contract. Find and summarize the key terms: payment terms, termination clause, and liability limits.',
        rubric: ['Reads document', 'Extracts specific sections', 'Summarizes clearly'],
        requires_tools: true,
        expected_tools: ['list_documents', 'read_document', 'query_document_content'],
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'mm_rag_001',
        category: :multimodal,
        name: 'RAG store query',
        scenario: 'User has a knowledge base.',
        request: 'Query our knowledge base for information about our refund policy.',
        rubric: ['Uses query_rag_store', 'Returns relevant content', 'Cites sources'],
        requires_tools: true,
        expected_tools: ['query_rag_store'],
        grounding_required: true,
        difficulty: :medium
      },

      # ============================================
      # AGENT DELEGATION TASKS
      # Tests that Scout properly delegates to specialists
      # ============================================
      {
        id: 'delegate_001',
        category: :agent_delegation,
        name: 'Delegate to Landing Page Agent',
        scenario: 'User needs a landing page created.',
        request: 'Create a landing page for my new SaaS product called "TaskMaster Pro" - a project management tool for remote teams.',
        rubric: ['Uses delegate_to_agent or invoke_agent_plugin', 'Delegates to ai_landing_page_creator', 'Provides task context'],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        expected_agent: 'ai_landing_page_creator',
        creates_asset: true,
        asset_type: :landing_page,
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'delegate_002',
        category: :agent_delegation,
        name: 'Delegate to Email Agent',
        scenario: 'User needs an email campaign.',
        request: 'Create a 3-email welcome sequence for new trial users of our software.',
        rubric: ['Delegates to email_sequence_architect', 'Provides sequence requirements', 'Returns email content'],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        expected_agent: 'email_sequence_architect',
        creates_asset: true,
        asset_type: :email_campaign,
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'delegate_003',
        category: :agent_delegation,
        name: 'Delegate to Integration Architect',
        scenario: 'User needs help setting up an integration.',
        request: 'Help me set up a Stripe integration to sync our customer data.',
        rubric: ['Delegates to integration_architect', 'Provides integration requirements', 'Guides through setup'],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        expected_agent: 'integration_architect',
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'delegate_004',
        category: :agent_delegation,
        name: 'Delegate to Research Agent',
        scenario: 'User needs deep research.',
        request: 'Do a comprehensive competitor analysis of the top 3 project management tools.',
        rubric: ['Delegates to web_research_specialist', 'Provides research scope', 'Returns detailed analysis'],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin', 'web_search'],
        expected_agent: 'web_research_specialist',
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'delegate_005',
        category: :agent_delegation,
        name: 'Delegate to Sales Email Agent',
        scenario: 'User needs personalized outreach.',
        request: 'Write a personalized cold outreach email to the CEO of Acme Corp about our consulting services.',
        rubric: ['Delegates to sales_email_generator or personalized_sales_email_writer', 'Provides context', 'Returns personalized email'],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        expected_agent: 'sales_email_generator',
        grounding_required: true,
        difficulty: :medium
      },
      {
        id: 'delegate_006',
        category: :agent_delegation,
        name: 'Ask agent for help',
        scenario: 'Scout needs specialist input.',
        request: 'I need help analyzing the ROI of a $50k marketing campaign that generated 200 leads and 20 customers worth $5k each.',
        rubric: ['Uses ask_agent_for_help', 'Consults roi_analysis_agent', 'Returns ROI calculation'],
        requires_tools: true,
        expected_tools: ['ask_agent_for_help'],
        expected_agent: 'roi_analysis_agent',
        grounding_required: true,
        difficulty: :medium
      },

      # ============================================
      # ASSET CREATION TASKS
      # Tests creating integrations, tools, agents
      # ============================================
      
      # Integration Creation (no-auth APIs)
      {
        id: 'create_int_001',
        category: :creation,
        name: 'Create JSONPlaceholder integration',
        scenario: 'Developer wants to test with a mock API.',
        request: 'Create an integration with JSONPlaceholder (https://jsonplaceholder.typicode.com) - a free fake API for testing. Add operations for listing posts and getting a single post.',
        rubric: ['Creates integration with create_integration_foundation', 'Sets no_auth', 'Adds operations', 'Tests successfully'],
        requires_tools: true,
        expected_tools: ['create_integration_foundation', 'configure_integration_auth', 'add_integration_operations'],
        creates_asset: true,
        asset_type: :integration,
        verify_asset: true,
        verification_endpoint: 'https://jsonplaceholder.typicode.com/posts/1',
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'create_int_002',
        category: :creation,
        name: 'Create Dog API integration',
        scenario: 'Fun API for testing.',
        request: 'Create an integration with the Dog CEO API (https://dog.ceo/api) to get random dog images. It\'s free and needs no authentication.',
        rubric: ['Creates integration', 'No auth required', 'Adds random image operation', 'Tests successfully'],
        requires_tools: true,
        expected_tools: ['create_integration_foundation', 'configure_integration_auth', 'add_integration_operations'],
        creates_asset: true,
        asset_type: :integration,
        verify_asset: true,
        verification_endpoint: 'https://dog.ceo/api/breeds/image/random',
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'create_int_003',
        category: :creation,
        name: 'Create public holiday API integration',
        scenario: 'HR needs holiday data.',
        request: 'Create an integration with the Nager.Date API (https://date.nager.at) to get public holidays. Add an operation to get US holidays for 2024.',
        rubric: ['Creates integration', 'No auth required', 'Adds holiday operation', 'Tests successfully'],
        requires_tools: true,
        expected_tools: ['create_integration_foundation', 'configure_integration_auth', 'add_integration_operations'],
        creates_asset: true,
        asset_type: :integration,
        verify_asset: true,
        verification_endpoint: 'https://date.nager.at/api/v3/publicholidays/2024/US',
        grounding_required: true,
        difficulty: :hard
      },

      # Tool Creation
      {
        id: 'create_tool_001',
        category: :creation,
        name: 'Create calculation tool',
        scenario: 'User needs a custom calculator.',
        request: 'Create a tool that calculates compound interest. It should take principal, rate, years, and compounding frequency as inputs.',
        rubric: ['Uses create_tool_definition', 'Defines parameters correctly', 'Implements calculation logic'],
        requires_tools: true,
        expected_tools: ['create_tool_definition', 'create_tool_tool'],
        creates_asset: true,
        asset_type: :tool,
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'create_tool_002',
        category: :creation,
        name: 'Create data formatting tool',
        scenario: 'User needs to format data.',
        request: 'Create a tool that converts a list of names from "First Last" format to "Last, First" format.',
        rubric: ['Creates tool definition', 'Handles list input', 'Transforms correctly'],
        requires_tools: true,
        expected_tools: ['create_tool_definition', 'create_tool_tool'],
        creates_asset: true,
        asset_type: :tool,
        grounding_required: true,
        difficulty: :medium
      },

      # Agent Creation
      {
        id: 'create_agent_001',
        category: :creation,
        name: 'Create industry research agent',
        scenario: 'User needs specialized research.',
        request: 'Create an agent specialized in researching the healthcare technology industry. It should be able to find news, analyze trends, and identify key players.',
        rubric: ['Uses create_agent_plugin', 'Defines clear role', 'Specifies capabilities', 'Sets appropriate tools'],
        requires_tools: true,
        expected_tools: ['create_agent_plugin', 'create_agent_tool'],
        creates_asset: true,
        asset_type: :agent,
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'create_agent_002',
        category: :creation,
        name: 'Create customer success agent',
        scenario: 'User needs CS automation.',
        request: 'Create an agent that helps with customer success tasks: analyzing NPS scores, drafting follow-up emails, and identifying at-risk customers.',
        rubric: ['Creates agent', 'Defines CS focus', 'Lists relevant capabilities'],
        requires_tools: true,
        expected_tools: ['create_agent_plugin', 'create_agent_tool'],
        creates_asset: true,
        asset_type: :agent,
        grounding_required: true,
        difficulty: :hard
      },

      # ============================================
      # COMPLEX ORCHESTRATION TASKS
      # Multi-step workflows requiring multiple tools + agents
      # ============================================
      {
        id: 'orch_001',
        category: :orchestration,
        name: 'Research and create landing page',
        scenario: 'Full marketing workflow.',
        request: 'Research the top 3 competitors in the CRM space, identify their key messaging, then create a landing page for our CRM that differentiates us.',
        rubric: ['Uses web_search for research', 'Analyzes competitors', 'Delegates to landing page agent', 'Creates differentiated page'],
        requires_tools: true,
        expected_tools: ['web_search', 'delegate_to_agent'],
        expected_agent: 'ai_landing_page_creator',
        creates_asset: true,
        asset_type: :landing_page,
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'orch_002',
        category: :orchestration,
        name: 'Data analysis and email campaign',
        scenario: 'Data-driven marketing.',
        request: 'Look at our contact database, identify contacts who haven\'t been contacted in 30 days, and create a re-engagement email campaign for them.',
        rubric: ['Uses get_data to query contacts', 'Filters by last contact date', 'Creates email campaign', 'Personalizes based on data'],
        requires_tools: true,
        expected_tools: ['get_data', 'delegate_to_agent'],
        expected_agent: 'email_sequence_architect',
        creates_asset: true,
        asset_type: :email_campaign,
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'orch_003',
        category: :orchestration,
        name: 'Integration + tool + report',
        scenario: 'Full automation workflow.',
        request: 'Create an integration with a weather API, then create a tool that uses it to get weather for a city, then generate a report showing weather for the top 5 US cities.',
        rubric: ['Creates integration', 'Creates tool using integration', 'Generates report with data'],
        requires_tools: true,
        expected_tools: ['create_integration_foundation', 'create_tool_definition', 'invoke_operation'],
        creates_asset: true,
        asset_type: :integration,
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'orch_004',
        category: :orchestration,
        name: 'Document analysis + action',
        scenario: 'Document-driven workflow.',
        request: 'Read my uploaded documents, find any contracts expiring in the next 90 days, and draft renewal reminder emails for each.',
        rubric: ['Lists and reads documents', 'Identifies contracts', 'Extracts expiration dates', 'Creates reminder emails'],
        requires_tools: true,
        expected_tools: ['list_documents', 'read_document', 'query_document_content'],
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'orch_005',
        category: :orchestration,
        name: 'Full business snapshot',
        scenario: 'Executive dashboard.',
        request: 'Give me a complete business snapshot: contact count, recent activity, connected integrations, AI usage this month, and any available agents.',
        rubric: ['Uses get_data for contacts', 'Uses list_connections', 'Uses get_token_usage', 'Uses list_available_agents', 'Synthesizes into report'],
        requires_tools: true,
        expected_tools: ['get_data', 'list_connections', 'get_token_usage', 'list_available_agents'],
        grounding_required: true,
        difficulty: :hard
      },
      {
        id: 'orch_006',
        category: :orchestration,
        name: 'Create agent that uses integration',
        scenario: 'Building autonomous capability.',
        request: 'Create a "Market Research Agent" that can use the web_search tool and any news API integrations we have to provide daily market intelligence reports.',
        rubric: ['Creates agent', 'Configures with appropriate tools', 'Links to integrations', 'Defines clear purpose'],
        requires_tools: true,
        expected_tools: ['create_agent_plugin', 'list_connections'],
        creates_asset: true,
        asset_type: :agent,
        grounding_required: true,
        difficulty: :hard
      },

      # ============================================
      # EXTREME CHALLENGES (Nearly Impossible)
      # Multi-agent orchestration, complex workflows
      # These are designed to push the system to its limits
      # ============================================
      {
        id: 'extreme_001',
        category: :extreme,
        name: 'Full GTM Stack Creation',
        scenario: 'Launching a new product from scratch.',
        request: 'I\'m launching "InvoiceNinja" - an AI-powered invoicing tool for freelancers at $19/month. I need you to: 1) Research the competitive landscape, 2) Create a landing page, 3) Create a 5-email welcome sequence, 4) Set up a Stripe integration for payments, and 5) Create a "Sales Assistant" agent that can answer product questions. Do all of this.',
        rubric: [
          'Performs competitive research with web_search',
          'Delegates to landing page agent - creates actual page',
          'Delegates to email agent - creates actual sequence',
          'Creates Stripe integration with proper auth config',
          'Creates Sales Assistant agent with product knowledge',
          'All 5 assets are created and functional'
        ],
        requires_tools: true,
        expected_tools: ['web_search', 'delegate_to_agent', 'create_integration_foundation', 'create_agent_plugin'],
        creates_asset: true,
        asset_types: [:landing_page, :email_campaign, :integration, :agent],
        multi_agent: true,
        grounding_required: true,
        difficulty: :extreme
      },
      {
        id: 'extreme_002',
        category: :extreme,
        name: 'Self-Improving System',
        scenario: 'Building autonomous capability.',
        request: 'Analyze my current system capabilities (available agents, tools, integrations), identify gaps in my business operations coverage, then create 2 new agents and 2 new tools to fill those gaps. Explain what you created and why.',
        rubric: [
          'Lists current agents with list_available_agents',
          'Lists current tools',
          'Lists current integrations',
          'Identifies capability gaps',
          'Creates 2 new agents that fill gaps',
          'Creates 2 new tools that fill gaps',
          'Provides clear rationale'
        ],
        requires_tools: true,
        expected_tools: ['list_available_agents', 'list_connections', 'create_agent_plugin', 'create_tool_definition'],
        creates_asset: true,
        asset_types: [:agent, :tool],
        expected_asset_count: 4,
        grounding_required: true,
        difficulty: :extreme
      },
      {
        id: 'extreme_003',
        category: :extreme,
        name: 'End-to-End Customer Journey',
        scenario: 'Complete marketing automation.',
        request: 'Build a complete customer acquisition funnel: 1) Research our target market (SMB owners), 2) Create a lead magnet landing page offering a "Free Business Health Check", 3) Create an email nurture sequence (5 emails over 2 weeks), 4) Create a "Lead Qualifier" agent that can score leads based on their responses, 5) Create a tool that calculates a business health score. Make sure everything works together.',
        rubric: [
          'Researches SMB owner pain points',
          'Creates lead magnet landing page',
          'Creates 5-email nurture sequence',
          'Creates Lead Qualifier agent',
          'Creates business health score tool',
          'Components are logically connected'
        ],
        requires_tools: true,
        expected_tools: ['web_search', 'delegate_to_agent', 'create_agent_plugin', 'create_tool_definition'],
        creates_asset: true,
        asset_types: [:landing_page, :email_campaign, :agent, :tool],
        multi_agent: true,
        grounding_required: true,
        difficulty: :extreme
      },
      {
        id: 'extreme_004',
        category: :extreme,
        name: 'Integration Pipeline',
        scenario: 'Building data infrastructure.',
        request: 'Create a complete data pipeline: 1) Create an integration with JSONPlaceholder API (for testing), 2) Create an integration with a weather API, 3) Create a tool that combines data from both APIs, 4) Create an agent that can use these tools to generate daily reports, 5) Test everything works by generating a sample report.',
        rubric: [
          'Creates JSONPlaceholder integration',
          'Creates weather API integration',
          'Creates data combination tool',
          'Creates reporting agent',
          'Generates actual sample report',
          'All components tested and working'
        ],
        requires_tools: true,
        expected_tools: ['create_integration_foundation', 'configure_integration_auth', 'add_integration_operations', 'create_tool_definition', 'create_agent_plugin'],
        creates_asset: true,
        asset_types: [:integration, :tool, :agent],
        expected_asset_count: 5,
        grounding_required: true,
        difficulty: :extreme
      },
      {
        id: 'extreme_005',
        category: :extreme,
        name: 'Competitive Intelligence System',
        scenario: 'Building market intelligence.',
        request: 'Build a competitive intelligence system for a B2B SaaS company: 1) Research and document our top 5 competitors, 2) Create a "Competitor Tracker" agent that monitors competitor news, 3) Create a tool that compares pricing across competitors, 4) Create a landing page showcasing our competitive advantages, 5) Generate an initial competitive analysis report using the system you built.',
        rubric: [
          'Researches 5 real competitors',
          'Creates Competitor Tracker agent',
          'Creates pricing comparison tool',
          'Creates competitive advantage landing page',
          'Generates actual analysis report',
          'System components work together'
        ],
        requires_tools: true,
        expected_tools: ['web_search', 'create_agent_plugin', 'create_tool_definition', 'delegate_to_agent'],
        creates_asset: true,
        asset_types: [:agent, :tool, :landing_page],
        multi_agent: true,
        grounding_required: true,
        difficulty: :extreme
      },
      {
        id: 'extreme_006',
        category: :extreme,
        name: 'Full Business Automation',
        scenario: 'Maximum automation challenge.',
        request: 'I want to automate as much of my consulting business as possible. Create: 1) An integration with a calendar API for scheduling, 2) A "Meeting Prep" agent that researches clients before calls, 3) A "Proposal Generator" agent that creates custom proposals, 4) A tool that calculates project pricing based on scope, 5) A landing page for booking discovery calls, 6) An email sequence for post-meeting follow-up. Show me everything working together.',
        rubric: [
          'Creates calendar integration',
          'Creates Meeting Prep agent',
          'Creates Proposal Generator agent',
          'Creates pricing calculation tool',
          'Creates booking landing page',
          'Creates follow-up email sequence',
          'Demonstrates integration between components'
        ],
        requires_tools: true,
        expected_tools: ['create_integration_foundation', 'create_agent_plugin', 'create_tool_definition', 'delegate_to_agent'],
        creates_asset: true,
        asset_types: [:integration, :agent, :tool, :landing_page, :email_campaign],
        expected_asset_count: 6,
        multi_agent: true,
        grounding_required: true,
        difficulty: :extreme
      },
      {
        id: 'extreme_007',
        category: :extreme,
        name: 'Agent Team Creation',
        scenario: 'Building an AI team.',
        request: 'Create a team of 3 specialized agents that work together: 1) A "Research Agent" that gathers market data, 2) An "Analysis Agent" that processes and interprets data, 3) A "Report Agent" that creates formatted reports. Each agent should be able to call the others when needed. Then test the team by having them collaborate on a market analysis for the CRM industry.',
        rubric: [
          'Creates Research Agent with web_search capability',
          'Creates Analysis Agent with data processing capability',
          'Creates Report Agent with formatting capability',
          'Agents can communicate/delegate to each other',
          'Team produces actual CRM market analysis',
          'Demonstrates multi-agent collaboration'
        ],
        requires_tools: true,
        expected_tools: ['create_agent_plugin', 'delegate_to_agent', 'web_search'],
        creates_asset: true,
        asset_types: [:agent],
        expected_asset_count: 3,
        multi_agent: true,
        grounding_required: true,
        difficulty: :extreme
      },
      {
        id: 'extreme_008',
        category: :extreme,
        name: 'Document to System',
        scenario: 'Converting knowledge to automation.',
        request: 'I have uploaded our company\'s sales playbook document. Read it, extract the key sales processes, then: 1) Create a "Sales Coach" agent that can answer questions about our sales methodology, 2) Create a tool that scores sales calls against our playbook criteria, 3) Create an email template library based on the playbook\'s recommended messages, 4) Create a landing page that highlights our sales approach for recruiting.',
        rubric: [
          'Reads and understands the sales playbook document',
          'Creates Sales Coach agent with playbook knowledge',
          'Creates call scoring tool',
          'Creates email templates from playbook',
          'Creates recruiting landing page',
          'All outputs reflect playbook content'
        ],
        requires_tools: true,
        expected_tools: ['list_documents', 'read_document', 'query_document_content', 'create_agent_plugin', 'create_tool_definition', 'delegate_to_agent'],
        creates_asset: true,
        asset_types: [:agent, :tool, :landing_page],
        multi_agent: true,
        requires_document: true,
        grounding_required: true,
        difficulty: :extreme
      }
    ].freeze

    class << self
      def all_tasks
        TASKS
      end

      def tasks_by_category(category)
        TASKS.select { |t| t[:category] == category.to_sym }
      end

      def task(task_id)
        TASKS.find { |t| t[:id] == task_id }
      end

      def by_difficulty(difficulty)
        TASKS.select { |t| t[:difficulty] == difficulty.to_sym }
      end

      def grounded_tasks
        TASKS.select { |t| t[:grounding_required] }
      end

      def creation_tasks
        TASKS.select { |t| t[:creates_asset] }
      end

      def delegation_tasks
        TASKS.select { |t| t[:expected_agent].present? }
      end

      def multimodal_tasks
        TASKS.select { |t| t[:category] == :multimodal }
      end

      def orchestration_tasks
        TASKS.select { |t| t[:category] == :orchestration }
      end

      def extreme_tasks
        TASKS.select { |t| t[:category] == :extreme }
      end

      def multi_agent_tasks
        TASKS.select { |t| t[:multi_agent] }
      end

      def summary
        {
          total: TASKS.size,
          by_category: CATEGORIES.keys.each_with_object({}) { |cat, h| h[cat] = tasks_by_category(cat).size },
          by_difficulty: { 
            easy: by_difficulty(:easy).size, 
            medium: by_difficulty(:medium).size, 
            hard: by_difficulty(:hard).size,
            extreme: by_difficulty(:extreme).size
          },
          grounded: grounded_tasks.size,
          creation: creation_tasks.size,
          delegation: delegation_tasks.size,
          multimodal: multimodal_tasks.size,
          orchestration: orchestration_tasks.size,
          extreme: extreme_tasks.size,
          multi_agent: multi_agent_tasks.size
        }
      end
    end
  end
end

