# Agent Plugin Seeds
# Creates example agent plugins to demonstrate the system

puts "🤖 Seeding Agent Plugins..."

# 1. Sales Email Generator Agent
sales_agent = AgentPlugin.create!(
  name: "Sales Email Generator",
  slug: "sales_email_generator",
  role: "executor",
  description: "Generates personalized sales emails based on lead data, company information, and pain points. Uses web research to customize messaging.",
  version: "1.0.0",
  status: "active",
  priority: 80,
  agent_class: "Agents::Specialized::ExecutorAgent",
  entity_id: nil,  # System-wide agent
  system_prompt: {
    prompt: "You are a sales email specialist. Generate compelling, personalized emails that address specific pain points. Keep it concise (under 150 words) and always include a clear call-to-action."
  },
  configuration: {
    max_email_length: 150,
    tone: "professional_friendly",
    include_ps: true
  }
)

# Add capabilities
sales_agent.agent_capabilities.create!([
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
])

# Add required tools
sales_agent.agent_tools.create!([
  { tool_name: "get_data", required: true },
  { tool_name: "web_search_tool", required: false },
  { tool_name: "create_object", required: true }
])

puts "  ✓ Created Sales Email Generator agent"

# 2. Content Analyzer Agent
analyzer_agent = AgentPlugin.create!(
  name: "Content Quality Analyzer",
  slug: "content_quality_analyzer",
  role: "verifier",
  description: "Analyzes content quality, readability, SEO optimization, and brand alignment. Provides actionable recommendations for improvement.",
  version: "1.0.0",
  status: "active",
  priority: 70,
  agent_class: "Agents::Specialized::ExecutorAgent",
  entity_id: nil,
  system_prompt: {
    prompt: "You are a content quality expert. Analyze content for readability, SEO, brand alignment, and engagement. Provide specific, actionable recommendations."
  },
  configuration: {
    min_readability_score: 60,
    check_seo: true,
    check_brand_voice: true
  }
)

analyzer_agent.agent_capabilities.create!([
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
])

analyzer_agent.agent_tools.create!([
  { tool_name: "get_data", required: true }
])

puts "  ✓ Created Content Quality Analyzer agent"

# 3. Campaign Optimizer Agent
optimizer_agent = AgentPlugin.create!(
  name: "Campaign Optimizer",
  slug: "campaign_optimizer",
  role: "analyst",
  description: "Analyzes campaign performance data and provides optimization recommendations. Identifies best-performing segments and suggests A/B test variations.",
  version: "1.0.0",
  status: "active",
  priority: 75,
  agent_class: "Agents::Specialized::ExecutorAgent",
  entity_id: nil,
  system_prompt: {
    prompt: "You are a marketing analytics expert. Analyze campaign data to identify optimization opportunities. Focus on actionable insights that improve conversion rates and ROI."
  },
  configuration: {
    min_sample_size: 100,
    confidence_level: 0.95
  }
)

optimizer_agent.agent_capabilities.create!([
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
])

optimizer_agent.agent_tools.create!([
  { tool_name: "get_data", required: true },
  { tool_name: "list_operations", required: false }
])

puts "  ✓ Created Campaign Optimizer agent"

# 4. Landing Page Creator Agent (Example of adaptive execution)
landing_page_agent = AgentPlugin.create!(
  name: "AI Landing Page Creator",
  slug: "ai_landing_page_creator",
  role: "executor",
  description: "Creates complete landing pages with AI-generated content, images, and CTAs. Adapts design based on industry best practices and brand guidelines.",
  version: "1.0.0",
  status: "active",
  priority: 85,
  agent_class: "Agents::Specialized::ExecutorAgent",
  entity_id: nil,
  system_prompt: {
    prompt: "You are a landing page specialist. Create high-converting landing pages that combine compelling copy with effective design. Follow conversion optimization best practices."
  },
  configuration: {
    include_hero_image: true,
    include_testimonials: false,
    include_faq: true
  }
)

landing_page_agent.agent_capabilities.create!([
  {
    capability_name: "landing_page_generation",
    contract_schema: {
      inputs: [
        { name: "product_description", type: "string", required: true },
        { name: "target_audience", type: "string", required: true },
        { name: "key_benefits", type: "array", required: true }
      ],
      outputs: [
        { name: "headline", type: "string" },
        { name: "subheadline", type: "string" },
        { name: "body_content", type: "string" },
        { name: "cta_text", type: "string" }
      ]
    }
  }
])

landing_page_agent.agent_tools.create!([
  { tool_name: "generate_ai_landing_page", required: true },
  { tool_name: "create_object", required: true }
])

puts "  ✓ Created AI Landing Page Creator agent"

# 5. Customer Journey Mapper Agent (Draft - for testing the workflow)
journey_agent = AgentPlugin.create!(
  name: "Customer Journey Mapper",
  slug: "customer_journey_mapper",
  role: "analyst",
  description: "Maps customer touchpoints and identifies friction points in the buyer journey. Suggests improvements to increase conversion rates.",
  version: "1.0.0",
  status: "draft",  # Not active yet
  priority: 60,
  agent_class: "Agents::Specialized::ExecutorAgent",
  entity_id: nil,
  system_prompt: {
    prompt: "You are a customer experience analyst. Map the complete customer journey and identify opportunities to reduce friction and improve conversion rates."
  },
  configuration: {
    analyze_touchpoints: true,
    identify_dropoff_points: true
  }
)

journey_agent.agent_capabilities.create!([
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
])

journey_agent.agent_tools.create!([
  { tool_name: "get_data", required: true }
])

puts "  ✓ Created Customer Journey Mapper agent (draft)"

puts "✅ Agent Plugin seeding complete!"
puts "   - #{AgentPlugin.active.count} active agents"
puts "   - #{AgentPlugin.where(status: 'draft').count} draft agents"
puts "   - #{AgentCapability.count} total capabilities"
puts "   - #{AgentTool.count} total tool bindings"
