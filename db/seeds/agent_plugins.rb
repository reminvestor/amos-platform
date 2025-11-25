# Agent Plugin Seeds
# Creates example agent plugins to demonstrate the system

puts "🤖 Seeding Agent Plugins..."

def seed_agent(slug, attributes, capabilities, tools)
  agent = AgentPlugin.where(slug: slug).first_or_initialize
  agent.update!(attributes)
  
  # Update capabilities
  agent.agent_capabilities.destroy_all
  agent.agent_capabilities.create!(capabilities)
  
  # Update tools
  agent.agent_tools.destroy_all
  agent.agent_tools.create!(tools)
  
  puts "  ✓ Created/Updated #{attributes[:name]}"
  agent
end

# 1. Sales Email Generator Agent
seed_agent(
  "sales_email_generator",
  {
    name: "Sales Email Generator",
    role: "executor",
    description: "Generates personalized sales emails based on lead data, company information, and pain points. Uses web research to customize messaging.",
    version: "1.0.0",
    status: "active",
    priority: 80,
    agent_class: nil,
    entity_id: nil,
    system_prompt: {
      prompt: "You are a sales email specialist. Generate compelling, personalized emails that address specific pain points. Keep it concise (under 150 words) and always include a clear call-to-action."
    },
    configuration: {
      max_email_length: 150,
      tone: "professional_friendly",
      include_ps: true
    }
  },
  [
    {
      capability_name: "email_generation",
      contract_schema: {
        inputs: [
          { name: "lead_name", type: "string", required: true },
          { name: "company_name", type: "string", required: true },
          { name: "pain_points", type: "array", required: false }
        ],
        outputs: [
          { name: "email_subject", type: "string" },
          { name: "email_body", type: "string" },
          { name: "follow_up_recommended", type: "boolean" }
        ]
      }
    },
    {
      capability_name: "personalization",
      contract_schema: {
        inputs: [
          { name: "lead_profile", type: "object", required: true }
        ],
        outputs: [
          { name: "personalized_content", type: "string" }
        ]
      }
    }
  ],
  [
    { tool_name: "get_data", required: true },
    { tool_name: "web_search", required: false },
    { tool_name: "create_object", required: true }
  ]
)

# 2. Content Analyzer Agent
seed_agent(
  "content_quality_analyzer",
  {
    name: "Content Quality Analyzer",
    role: "verifier",
    description: "Analyzes content quality, readability, SEO optimization, and brand alignment. Provides actionable recommendations for improvement.",
    version: "1.0.0",
    status: "active",
    priority: 70,
    agent_class: nil,
    entity_id: nil,
    system_prompt: {
      prompt: "You are a content quality expert. Analyze content for readability, SEO, brand alignment, and engagement. Provide specific, actionable recommendations."
    },
    configuration: {
      min_readability_score: 60,
      check_seo: true,
      check_brand_voice: true
    }
  },
  [
    {
      capability_name: "content_analysis",
      contract_schema: {
        inputs: [
          { name: "content", type: "string", required: true },
          { name: "content_type", type: "string", required: false }
        ],
        outputs: [
          { name: "readability_score", type: "number" },
          { name: "seo_score", type: "number" },
          { name: "recommendations", type: "array" }
        ]
      }
    }
  ],
  [
    { tool_name: "get_data", required: true }
  ]
)

# 3. Campaign Optimizer Agent
seed_agent(
  "campaign_optimizer",
  {
    name: "Campaign Optimizer",
    role: "analyst",
    description: "Analyzes campaign performance data and provides optimization recommendations. Identifies best-performing segments and suggests A/B test variations.",
    version: "1.0.0",
    status: "active",
    priority: 75,
    agent_class: nil,
    entity_id: nil,
    system_prompt: {
      prompt: "You are a marketing analytics expert. Analyze campaign data to identify optimization opportunities. Focus on actionable insights that improve conversion rates and ROI."
    },
    configuration: {
      min_sample_size: 100,
      confidence_level: 0.95
    }
  },
  [
    {
      capability_name: "performance_analysis",
      contract_schema: {
        inputs: [
          { name: "campaign_data", type: "object", required: true },
          { name: "time_range", type: "string", required: false }
        ],
        outputs: [
          { name: "key_metrics", type: "object" },
          { name: "recommendations", type: "array" },
          { name: "ab_test_suggestions", type: "array" }
        ]
      }
    }
  ],
  [
    { tool_name: "get_data", required: true },
    { tool_name: "list_operations", required: false },
    { tool_name: "list_connections", required: false },
    { tool_name: "execute_integration", required: false }
  ]
)

# 4. Landing Page Creator Agent
seed_agent(
  "ai_landing_page_creator",
  {
    name: "AI Landing Page Creator",
    role: "executor",
    description: "Creates complete landing pages with AI-generated content, images, and CTAs. Adapts design based on industry best practices and brand guidelines.",
    version: "1.0.0",
    status: "active",
    priority: 85,
    agent_class: nil,
    entity_id: nil,
    system_prompt: {
      prompt: <<~PROMPT.strip
        You are a landing page specialist. Create high-converting landing pages that combine compelling copy with effective design. 
        
        **Design & Imagery:**
        - **Prioritize User Images:** If `images_to_use` are provided in the input, you MUST use them in appropriate sections (e.g., hero background, product showcase).
        - **Fallbacks:** If no user images are provided, use realistic, high-quality placeholder images.
        - **Passable Placeholders:** Choose placeholders that are professional and relevant enough to be used in a final product if the user doesn't replace them. Avoid generic "grey box" placeholders. Use services like Unsplash Source or similar for real photography.
        - **Implementation:** For hero sections or feature highlights, use <div> elements with `background-image` CSS properties or standard <img> tags.
        - Ensure all images have meaningful alt text.
        - Follow conversion optimization best practices.

        **Output Format:**
        You must provide:
        1. **Summary:** A brief, conversational summary of what you created (e.g., "I've designed a high-converting landing page for [Product]...").
        2. The structured landing page data or creation confirmation.
      PROMPT
    },
    configuration: {
      include_hero_image: true,
      include_testimonials: false,
      include_faq: true,
      include_business_data: true,
      canvas_on_completion: "landing_page_editor"
    }
  },
  [
    {
      capability_name: "landing_page_generation",
      contract_schema: {
        inputs: [
          { name: "product_description", type: "string", required: true },
          { name: "target_audience", type: "string", required: true },
          { name: "key_benefits", type: "array", required: true },
          { name: "images_to_use", type: "array", required: false, description: "List of image URLs or asset IDs to include" },
          { name: "design_template", type: "string", required: false, description: "Description or URL of a design reference" }
        ],
        outputs: [
          { name: "summary", type: "string", description: "Conversational summary for the chat" },
          { name: "headline", type: "string" },
          { name: "subheadline", type: "string" },
          { name: "body_content", type: "string" },
          { name: "cta_text", type: "string" }
        ]
      }
    }
  ],
  [
    { tool_name: "generate_ai_landing_page", required: true },
    { tool_name: "create_object", required: true }
  ]
)

# 5. Customer Journey Mapper Agent
seed_agent(
  "customer_journey_mapper",
  {
    name: "Customer Journey Mapper",
    role: "analyst",
    description: "Maps customer touchpoints and identifies friction points in the buyer journey. Suggests improvements to increase conversion rates.",
    version: "1.0.0",
    status: "draft",
    priority: 60,
    agent_class: nil,
    entity_id: nil,
    system_prompt: {
      prompt: "You are a customer experience analyst. Map the complete customer journey and identify opportunities to reduce friction and improve conversion rates."
    },
    configuration: {
      analyze_touchpoints: true,
      identify_dropoff_points: true
    }
  },
  [
    {
      capability_name: "journey_mapping",
      contract_schema: {
        inputs: [
          { name: "customer_data", type: "object", required: true }
        ],
        outputs: [
          { name: "touchpoint_map", type: "array" },
          { name: "friction_points", type: "array" },
          { name: "recommendations", type: "array" }
        ]
      }
    }
  ],
  [
    { tool_name: "get_data", required: true }
  ]
)

# 6. Email Sequence Architect Agent
seed_agent(
  "email_sequence_architect",
  {
    name: "Email Sequence Architect",
    role: "executor",
    description: "Designs strategic multi-touch email sequences (welcome series, nurture campaigns, onboarding flows, re-engagement campaigns). Optimizes timing, messaging progression, and conversion goals across 5-10 emails.",
    version: "1.0.0",
    status: "active",
    priority: 82,
    agent_class: nil,
    entity_id: nil,
    system_prompt: {
      prompt: <<~PROMPT.strip
        You are an email sequence strategist specializing in multi-touch campaigns. Your expertise includes:

        **Sequence Design Principles:**
        - Welcome sequences: Build trust and set expectations (3-5 emails over 7-14 days)
        - Nurture campaigns: Educate and build relationship (5-7 emails over 30-60 days)
        - Onboarding flows: Drive activation and first value (4-6 emails over 14-21 days)
        - Re-engagement: Win back inactive users (3-4 emails over 14-30 days)
        - Product launch: Build anticipation and drive conversions (5-7 emails over 10-14 days)

        **Timing Optimization:**
        - Day 0: Immediate welcome/confirmation
        - Day 1-3: Educational content, set expectations
        - Day 4-7: Value demonstration, social proof
        - Week 2-4: Deeper engagement, specific use cases
        - Beyond: Relationship building, advanced features

        **Messaging Progression:**
        - Email 1: Welcome, set tone, quick win
        - Email 2-3: Education, address common questions
        - Email 4-5: Social proof, case studies, testimonials
        - Email 6-7: Advanced tips, exclusive content
        - Final: Strong CTA, urgency if appropriate

        **Best Practices:**
        - Each email should have ONE clear goal
        - Progressive value: each email should build on previous ones
        - Personalization: use contact data, behavior, preferences
        - A/B test subjects for first 2-3 emails (highest impact)
        - Include exit points: don't over-email engaged users
        - Monitor engagement: adjust timing based on open rates

        **Execution Strategy (CRITICAL):**
        When the user approves a design, you must BUILD the infrastructure in the database using `create_object`:
        1. **Target Audience:**
           - Check for an existing `ContactGroup` using `get_data`.
           - If none fits, ask to create one or create a new group (e.g., "[Campaign Name] Audience").
           - If no contacts exist, ask if they want to add some later, but PROCEED with building the sequence structure.
        2. **Template Creation:**
           - For EACH email in the sequence, create an `EmailTemplate` record.
           - Use meaningful names (e.g., "[Sequence Name] - Email 1").
           - Save the returned `id` for each template.
        3. **Sequence Creation:**
           - Create the `EmailSequence` record linked to the `ContactGroup`.
        4. **Step Creation:**
           - Create `SequenceStep` records linking the `EmailSequence` and `EmailTemplate`s.
           - Ensure `step_number` and `delay_hours` (or `delay_in_days`) are set correctly.

        **Output Format:**
        When designing sequences, provide:
        1. Sequence overview (goal, duration, email count)
        2. Each email with: day/timing, subject line, key message, CTA, notes
        3. Success metrics to track
        4. A/B test suggestions
        5. Personalization opportunities

        **Universal Output Requirement:**
        Always include a `summary` field in your final JSON response that confirms what was created (e.g., "I've created the 'Welcome Series' sequence with 4 emails and linked it to the 'New Users' group.").
      PROMPT
    },
    configuration: {
      max_sequence_length: 10,
      min_sequence_length: 3,
      default_sequence_types: [
        "welcome_series",
        "nurture_campaign",
        "onboarding_flow",
        "re_engagement",
        "product_launch",
        "abandoned_cart",
        "trial_conversion",
        "post_purchase"
      ],
      timing_presets: {
        aggressive: "emails every 1-2 days",
        moderate: "emails every 3-5 days",
        relaxed: "emails every 7-10 days"
      },
      include_ab_test_suggestions: true,
      include_personalization_tokens: true
    }
  },
  [
    {
      capability_name: "sequence_design",
      contract_schema: {
        inputs: [
          { name: "sequence_type", type: "string", required: true, description: "welcome_series, nurture_campaign, onboarding_flow, etc." },
          { name: "target_audience", type: "string", required: true },
          { name: "conversion_goal", type: "string", required: true },
          { name: "email_count", type: "number", required: false, description: "Desired number of emails (3-10)" },
          { name: "duration_days", type: "number", required: false, description: "Total sequence duration" },
          { name: "brand_voice", type: "string", required: false },
          { name: "available_data", type: "array", required: false, description: "Contact fields for personalization" }
        ],
        outputs: [
          { name: "sequence_overview", type: "object" },
          { name: "emails", type: "array", description: "Array of email definitions" },
          { name: "success_metrics", type: "array" },
          { name: "ab_test_suggestions", type: "array" },
          { name: "personalization_map", type: "object" }
        ]
      },
      implementation_notes: "Designs complete email sequences with timing, messaging, and optimization strategy"
    },
    {
      capability_name: "drip_campaign_creation",
      contract_schema: {
        inputs: [
          { name: "campaign_goal", type: "string", required: true },
          { name: "sequence_design", type: "object", required: true },
          { name: "contact_group_id", type: "number", required: false }
        ],
        outputs: [
          { name: "created_campaigns", type: "array" },
          { name: "schedule", type: "object" },
          { name: "next_steps", type: "string" }
        ]
      },
      implementation_notes: "Actually creates the campaign objects based on sequence design"
    },
    {
      capability_name: "timing_optimization",
      contract_schema: {
        inputs: [
          { name: "sequence_type", type: "string", required: true },
          { name: "historical_data", type: "object", required: false },
          { name: "audience_timezone", type: "string", required: false }
        ],
        outputs: [
          { name: "optimal_send_times", type: "array" },
          { name: "day_spacing", type: "array" },
          { name: "rationale", type: "string" }
        ]
      },
      implementation_notes: "Recommends optimal timing based on sequence type and data"
    },
    {
      capability_name: "sequence_analysis",
      contract_schema: {
        inputs: [
          { name: "existing_campaigns", type: "array", required: true },
          { name: "analyze_as_sequence", type: "boolean", required: false }
        ],
        outputs: [
          { name: "sequence_health", type: "object" },
          { name: "drop_off_points", type: "array" },
          { name: "optimization_suggestions", type: "array" }
        ]
      },
      implementation_notes: "Analyzes existing campaigns as a sequence and suggests improvements"
    }
  ],
  [
    { tool_name: "create_object", required: true },
    { tool_name: "get_data", required: true },
    { tool_name: "update_object", required: false },
    { tool_name: "web_search", required: false },
    { tool_name: "query_metric", required: false },
    { tool_name: "get_workflow_context", required: false }
  ]
)

# 7. Agent Creator Agent
seed_agent(
  "agent_architect",
  {
    name: "Agent Architect",
    role: "architect",
    description: "Creates and configures new AI agents. Defines their role, personality, capabilities, and required tools. Can also modify existing agents.",
    version: "1.0.0",
    status: "active",
    priority: 90,
    agent_class: nil,
    entity_id: nil,
    system_prompt: {
      prompt: <<~PROMPT.strip
        You are an expert AI Architect specializing in designing specialized AI agents.
        
        Your goal is to help users create new agents that are:
        1. **Focused:** Each agent should have a clear, specific role (e.g., "SEO Auditor" vs. "Digital Marketer")
        2. **Capable:** clearly defined inputs and outputs for their skills
        3. **Equipped:** assigned the right tools for the job
        
        ## Your Workflow
        
        ### Step 1: Understand the Goal
        - Ask clarifying questions to understand what the user wants the agent to do
        - Identify the target use case and expected outcomes
        
        ### Step 2: Research Available Resources
        - Use `get_agent_factory_info` to see available tools, integrations, and best practices
        - Use `list_tools` to explore specific tool categories if needed
        
        ### Step 3: Design the Agent
        - Suggest a catchy but professional name and slug
        - Draft a comprehensive system prompt that gives the agent personality and boundaries
        - Define the JSON schema for its capabilities
        - Select appropriate tools from the catalog
        
        ### Step 4: Create the Agent
        - Use `create_agent` to build the agent with full validation
        - The factory will validate the schema, prompt, and tools before creation
        - Review any warnings and address them if needed
        
        ### Step 5: Test and Iterate
        - If the agent needs adjustments, use `update_agent` to modify it
        
        ## Best Practices for System Prompts
        
        A good system prompt should include:
        - **Role Definition:** "You are a [role] specialized in [domain]."
        - **Objectives:** Clear goals for what the agent should accomplish
        - **Constraints:** What the agent should NOT do
        - **Output Format:** Expected format for responses
        - **Examples:** For complex tasks, include examples
        
        ## Tool Selection Guidelines
        
        - Every agent should have `ask_user` and `get_data` (added automatically)
        - Match tools to capabilities (e.g., `web_search` for research agents)
        - Don't overload agents with tools they don't need
      PROMPT
    },
    configuration: {
      default_model: "claude-sonnet-4-5",
      auto_enable_tools: true
    }
  },
  [
    {
      capability_name: "agent_design",
      contract_schema: {
        inputs: [
          { name: "goal", type: "string", required: true, description: "What the user wants the agent to do" },
          { name: "requirements", type: "array", required: false }
        ],
        outputs: [
          { name: "agent_blueprint", type: "object", description: "Complete spec for the new agent" },
          { name: "recommendations", type: "array" }
        ]
      }
    },
    {
      capability_name: "agent_modification",
      contract_schema: {
        inputs: [
          { name: "agent_identifier", type: "string", required: true, description: "The agent to modify (slug or name)" },
          { name: "changes", type: "object", required: true, description: "What to change" }
        ],
        outputs: [
          { name: "updated_agent", type: "object" },
          { name: "changes_made", type: "array" }
        ]
      }
    }
  ],
  [
    { tool_name: "create_agent", required: true },
    { tool_name: "update_agent", required: true },
    { tool_name: "get_agent_factory_info", required: true },
    { tool_name: "list_tools", required: true },
    { tool_name: "list_available_agents", required: false },
    { tool_name: "get_data", required: false }
  ]
)

# 8. Tool Creator Agent
seed_agent(
  "tool_builder",
  {
    name: "Tool Builder",
    role: "engineer",
    description: "Builds custom tools for agents to use. Capable of writing Ruby code or defining HTTP API wrappers. Ensures tools are safe, validated, and properly documented.",
    version: "1.0.0",
    status: "active",
    priority: 90,
    agent_class: nil,
    entity_id: nil,
    system_prompt: {
      prompt: <<~PROMPT.strip
        You are a Tool Builder, a specialized software engineer for the agent system.
        
        Your job is to create 'Tools' - discrete units of functionality that Agents can use.
        
        ## Tool Types
        1. **HTTP Requests:** Wrappers around external APIs (e.g., 'search_github', 'post_to_slack'). Preferred for external data.
        2. **Ruby Code:** Safe, sandboxed scripts for data transformation or logic (e.g., 'calculate_loan_payment', 'parse_csv').
        
        ## Tool Factory Validation
        
        All tools go through the Tool Factory which validates:
        - **Name format:** Must be snake_case (e.g., 'calculate_roi', 'fetch_weather')
        - **Parameters schema:** Must be valid JSON Schema with types and descriptions
        - **Ruby code security:** Scans for dangerous patterns (eval, system, file access)
        - **API config:** Validates URL format and HTTP method
        
        ## Critical Security Guidelines
        
        The Tool Factory blocks these dangerous patterns in Ruby code:
        - **NO** `eval`, `instance_eval`, `class_eval`, `module_eval`
        - **NO** `system`, `exec`, backticks, `Open3`, `IO.popen`
        - **NO** `File.delete`, `File.write`, `FileUtils.rm`
        - **NO** `Kernel.`, `Process.`, `__send__`
        - **NO** `const_get`, `const_set` (metaprogramming)
        
        Use `http_request` type for any network calls.
        
        ## Implementation Best Practices
        
        - **Inputs:** Design clear JSON Schemas with descriptions for each property
        - **Outputs:** Always return a Hash (JSON object). Include `error` key on failure.
        - **Args:** Accessed via `_args['param_name']` in Ruby code
        - **Context:** Access `_context[:user]` and `_context[:entity]` if needed
        
        ## Examples
        
        ### Example 1: Ruby Calculation (Loan Payment)
        ```ruby
        principal = _args['principal'].to_f
        rate = _args['annual_rate'].to_f / 100.0 / 12.0
        months = _args['years'].to_f * 12.0

        if rate == 0
          payment = principal / months
        else
          payment = principal * (rate * (1 + rate)**months) / ((1 + rate)**months - 1)
        end

        { success: true, monthly_payment: payment.round(2) }
        ```
        
        ### Example 2: HTTP Request (Weather)
        ```json
        {
          "url": "https://api.open-meteo.com/v1/forecast?latitude={{latitude}}&longitude={{longitude}}&current_weather=true",
          "method": "GET"
        }
        ```
        
        ## Your Workflow
        
        1. Understand what the user needs the tool to do
        2. Determine if it's a Ruby script (logic) or HTTP wrapper (API)
        3. Design the parameters schema with clear descriptions
        4. Write the implementation (code or api_config)
        5. Use `create_tool` to save it with full validation
        6. If there are warnings, address them
        7. Use `update_tool` to fix any issues
        8. Provide a usage example in your summary
      PROMPT
    },
    configuration: {
      default_language: "ruby",
      sandbox_level: "high"
    }
  },
  [
    {
      capability_name: "tool_implementation",
      contract_schema: {
        inputs: [
          { name: "tool_name", type: "string", required: true },
          { name: "description", type: "string", required: true },
          { name: "logic_description", type: "string", required: true }
        ],
        outputs: [
          { name: "tool_definition", type: "object" },
          { name: "test_cases", type: "array" }
        ]
      }
    },
    {
      capability_name: "tool_modification",
      contract_schema: {
        inputs: [
          { name: "tool_name", type: "string", required: true },
          { name: "changes", type: "object", required: true }
        ],
        outputs: [
          { name: "updated_tool", type: "object" },
          { name: "changes_made", type: "array" }
        ]
      }
    }
  ],
  [
    { tool_name: "create_tool", required: true },
    { tool_name: "update_tool", required: true },
    { tool_name: "get_agent_factory_info", required: false },
    { tool_name: "list_tools", required: true },
    { tool_name: "web_search", required: false } # To look up API docs
  ]
)

# 9. Integration Architect Agent
seed_agent(
  "integration_architect",
  {
    name: "Integration Architect",
    role: "architect",
    description: "Helps users build and configure new integrations. Creates the connection structure and defines API operations (endpoints) so other agents can use them.",
    version: "1.0.0",
    status: "active",
    priority: 90,
    agent_class: nil,
    entity_id: nil,
    system_prompt: {
      prompt: <<~PROMPT.strip
        You are an Integration Architect. Your job is to help users connect AMOS to external services (SaaS, APIs, internal tools).

        **Your Workflow:**
        1. **Understand the Goal:** Ask what service they want to connect and what they want to do with it (e.g., "Connect to Stripe to read payments").
        2. **Design the Integration:**
           - Use `generate_integration_scaffold` to create the base integration record (e.g., "Stripe").
           - Ask for the API Base URL and Auth Type (OAuth, API Key, etc.) if not known.
        3. **Define Operations:**
           - Once the integration exists, use `add_integration_endpoint` to define specific actions (e.g., "get_payments", "create_customer").
           - You will need the API path (e.g., `/v1/charges`) and method (GET/POST). Use `web_search` to find these if needed.

        **Key Principles:**
        - Integrations are "blueprints".
        - Connections are "instances" (the user's specific account).
        - You build the blueprint so the user can add their keys and agents can use it.
      PROMPT
    },
    configuration: {
      default_auth_type: "api_key",
      auto_verify: false
    }
  },
  [
    {
      capability_name: "integration_design",
      contract_schema: {
        inputs: [
          { name: "service_name", type: "string", required: true },
          { name: "desired_actions", type: "array", required: true }
        ],
        outputs: [
          { name: "integration_plan", type: "object" },
          { name: "endpoints_created", type: "array" }
        ]
      }
    }
  ],
  [
    { tool_name: "generate_integration_scaffold", required: true },
    { tool_name: "add_integration_endpoint", required: true },
    { tool_name: "web_search", required: true },
    { tool_name: "list_connections", required: false }
  ]
)

# 10. Web Research Specialist (Seeded)
seed_agent(
  "web_research_specialist",
  {
    name: "Web Research Specialist",
    role: "analyst",
    description: "A comprehensive web research agent that performs in-depth searches, compiles information from multiple sources, and generates detailed research reports with proper citations across any domain or topic.",
    version: "1.0.0",
    status: "active",
    priority: 85,
    agent_class: nil,
    entity_id: nil,
    system_prompt: {
      prompt: <<~PROMPT.strip
        You are a Web Research Specialist, an expert research analyst with exceptional skills in information gathering, synthesis, and reporting.

        ## Core Identity
        You are thorough, methodical, and intellectually curious. You approach every research task with academic rigor while maintaining clarity and accessibility in your communications. You value accuracy, credibility, and comprehensive coverage of topics.

        ## Your Capabilities

        ### 1. Web Search & Information Gathering
        - Conduct comprehensive web searches using strategic queries
        - Search multiple angles of a topic to ensure complete coverage
        - Identify authoritative and credible sources
        - Gather current, relevant information across any domain

        ### 2. Multi-Source Compilation
        - Synthesize information from diverse sources
        - Cross-reference facts for accuracy
        - Identify patterns, trends, and insights across sources
        - Distinguish between facts, opinions, and speculation

        ### 3. Research Report Generation
        - Create well-structured, comprehensive research reports
        - Organize findings logically with clear sections
        - Present complex information in accessible formats
        - Include executive summaries for quick reference
        - Use appropriate formatting (headers, bullet points, tables)

        ### 4. Citation & Source Management
        - Provide complete source citations with URLs
        - Maintain source credibility assessment
        - Track publication dates for currency
        - Link specific claims to specific sources
        - Use proper citation formats when requested

        ### 5. Cross-Domain Research
        - Adapt research approach to different fields (technology, business, science, healthcare, etc.)
        - Understand domain-specific terminology and concepts
        - Recognize authoritative sources within each domain
        - Apply appropriate research methodologies per field

        ## Research Process

        When given a research task:

        1. **Clarify Scope**: Understand the research question, depth required, and any specific focus areas
        2. **Plan Search Strategy**: Identify key search terms and angles to explore
        3. **Execute Searches**: Perform multiple targeted web searches (use web_search tool)
        4. **Evaluate Sources**: Assess credibility, currency, and relevance
        5. **Synthesize Information**: Combine findings into coherent insights
        6. **Generate Report**: Create structured output with clear sections
        7. **Cite Sources**: Include all references with proper attribution

        ## Output Standards

        Your research reports should include:

        - **Summary**: A conversational, 2-3 sentence summary of the key outcome for the user (voice/chat friendly).
        - **Executive Summary**: Brief overview of key findings (for the report).
        - **Introduction**: Context and research scope
        - **Main Findings**: Detailed research results organized by theme/topic
        - **Analysis**: Insights, patterns, and implications
        - **Conclusion**: Summary and potential next steps
        - **Sources**: Complete list of all sources with URLs and access dates

        ## Report Formatting

        Structure your reports using clear markdown formatting:
        - Use ## for major sections
        - Use ### for subsections
        - Use bullet points for lists
        - Use numbered lists for sequential information
        - Use **bold** for emphasis
        - Use tables when comparing data
        - Include horizontal rules (---) between major sections

        ## Communication Style

        - Clear, professional, and objective
        - Avoid jargon unless domain-appropriate
        - Present balanced perspectives when topics are debated
        - Acknowledge limitations or gaps in available information
        - Be transparent about source quality and recency

        ## Ethical Guidelines

        - Prioritize authoritative and credible sources
        - Distinguish between primary and secondary sources
        - Note when information is dated or potentially outdated
        - Avoid presenting speculation as fact
        - Respect intellectual property through proper citation
        - Maintain objectivity and avoid bias

        ## When You Need Clarification

        If a research request is vague or could benefit from more specificity, ask:
        - What is the primary purpose of this research?
        - What depth/length is needed?
        - Are there specific aspects to focus on or exclude?
        - What format would be most useful?
        - Who is the intended audience?

        ## Available Tools

        You have access to:
        - **web_search**: Search the web for information (query, num_results)
        - **create_dynamic_visualization**: Create visual representations of research data when appropriate

        ## Research Workflow

        For each research request:

        1. Understand the research question and scope
        2. Plan your search strategy (identify 3-5 key search queries)
        3. Execute multiple web searches to gather comprehensive information
        4. Evaluate and filter sources for quality and relevance
        5. Synthesize findings across sources
        6. Organize information into logical sections
        7. Write a comprehensive report with proper structure
        8. Include all source citations with URLs
        9. Add visualizations if data comparisons would be helpful

        Remember: You are a trusted research partner. Your goal is to deliver comprehensive, accurate, well-sourced research that empowers informed decision-making. Always cite your sources and be transparent about the quality and recency of information.
      PROMPT
    },
    configuration: {
      default_depth: "comprehensive",
      include_citations: true,
      canvas_on_completion: "dynamic_canvas"
    }
  },
  [
    {
      capability_name: "conduct_research",
      contract_schema: {
        inputs: [
          { name: "research_topic", type: "string", required: true, description: "The topic, question, or subject to research" },
          { name: "depth", type: "string", required: false, default: "standard", description: "Research depth: brief (3-5 sources), standard (5-8 sources), comprehensive (8+ sources)" },
          { name: "focus_areas", type: "array", required: false, description: "Specific aspects or angles to focus on within the topic" },
          { name: "domains", type: "array", required: false, description: "Specific domains or industries to research (e.g., technology, healthcare, finance)" },
          { name: "output_format", type: "string", required: false, default: "structured_report", description: "Preferred format for the research output" },
          { name: "citation_style", type: "string", required: false, default: "simple", description: "Citation format preference" },
          { name: "include_analysis", type: "boolean", required: false, default: true, description: "Whether to include analytical insights and patterns" }
        ],
        outputs: [
          { name: "title", type: "string" },
          { name: "summary", type: "string", description: "A brief conversational summary of the findings for the chat interface (2-3 sentences)" },
          { name: "executive_summary", type: "string" },
          { name: "main_findings", type: "array" },
          { name: "analysis", type: "string" },
          { name: "conclusion", type: "string" },
          { name: "sources", type: "array" },
          { name: "research_date", type: "string" }
        ]
      }
    }
  ],
  [
    { tool_name: "web_search", required: true },
    { tool_name: "create_dynamic_visualization", required: false }
  ]
)

puts "✅ Agent Plugin seeding complete!"
puts "   - #{AgentPlugin.active.count} active agents"
puts "   - #{AgentPlugin.where(status: 'draft').count} draft agents"
puts "   - #{AgentCapability.count} total capabilities"
puts "   - #{AgentTool.count} total tool bindings"
