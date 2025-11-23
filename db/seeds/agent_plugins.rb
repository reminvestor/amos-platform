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
    { tool_name: "list_operations", required: false }
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
        - Use realistic placeholder images instead of empty colored blocks where possible.
        - For hero sections or feature highlights, use high-quality placeholder URLs (e.g., from generic placeholder services) or create <div> elements with CSS background-images set to placeholder URLs.
        - Ensure image placeholders have meaningful alt text or descriptions.
        - Follow conversion optimization best practices.
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

        **Output Format:**
        When designing sequences, provide:
        1. Sequence overview (goal, duration, email count)
        2. Each email with: day/timing, subject line, key message, CTA, notes
        3. Success metrics to track
        4. A/B test suggestions
        5. Personalization opportunities

        Always ask about:
        - Sequence goal (welcome, nurture, onboard, re-engage, launch)
        - Target audience characteristics
        - Desired outcome/conversion goal
        - Any existing brand voice or content guidelines
        - Available contact data for personalization
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
        
        When creating an agent:
        - Ask clarifying questions to understand the user's goal
        - Suggest a catchy but professional name and slug
        - Draft a comprehensive system prompt that gives the agent personality and boundaries
        - Define the JSON schema for its capabilities
        - Select appropriate tools from the catalog
        
        Use the `create_agent_plugin` tool to actually build the agent in the system once the design is finalized.
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
    }
  ],
  [
    { tool_name: "create_agent_plugin", required: true },
    { tool_name: "list_tools", required: true },
    { tool_name: "get_data", required: false }
  ]
)

# 8. Tool Creator Agent
seed_agent(
  "tool_builder",
  {
    name: "Tool Builder",
    role: "engineer",
    description: "Builds custom tools for agents to use. capable of writing Ruby code or defining HTTP API wrappers. Ensures tools are safe and properly documented.",
    version: "1.0.0",
    status: "active",
    priority: 90,
    agent_class: nil,
    entity_id: nil,
    system_prompt: {
      prompt: <<~PROMPT.strip
        You are a Tool Builder, a specialized software engineer for the agent system.
        
        Your job is to create 'Tools' - discrete units of functionality that Agents can use.
        Tools can be:
        1. **HTTP Requests:** Wrappers around external APIs (e.g., 'search_github', 'post_to_slack')
        2. **Ruby Code:** Safe, sandboxed scripts for data transformation or logic (e.g., 'calculate_loan_schedule', 'parse_csv')
        
        When a user asks for a tool:
        1. Determine if it needs an external API or internal logic.
        2. Design the `input_schema` (JSON Schema) so agents know how to call it.
        3. Write the implementation (Ruby code or API config).
        4. Use `create_tool_definition` to save it to the database.
        
        **Security Warning:** When writing Ruby code, ensure it is self-contained and efficient. Avoid infinite loops or heavy IO.
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
    }
  ],
  [
    { tool_name: "create_tool_definition", required: true },
    { tool_name: "web_search", required: false } # To look up API docs
  ]
)

puts "✅ Agent Plugin seeding complete!"
puts "   - #{AgentPlugin.active.count} active agents"
puts "   - #{AgentPlugin.where(status: 'draft').count} draft agents"
puts "   - #{AgentCapability.count} total capabilities"
puts "   - #{AgentTool.count} total tool bindings"