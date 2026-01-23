# frozen_string_literal: true

# Seed file for CRM Agent
# This agent specializes in opportunity and sales pipeline management

puts "🤝 Seeding CRM Agent..."

# Create the CRM Agent (system-wide, entity: nil)
agent = AgentPlugin.find_or_initialize_by(
  slug: "crm_agent"
)

agent.update!(
  name: "CRM Agent",
  description: <<~DESC.strip,
    Specialized agent for Customer Relationship Management (CRM) and sales pipeline tasks.
    
    Handles the complete sales process:
    - Managing opportunities through pipeline stages (lead → qualified → proposal → negotiation → closed)
    - Logging activities (calls, emails, notes, meetings)
    - Creating and managing tasks for follow-ups
    - Assigning contacts and opportunities to team members or other AI agents
    - Tracking lead scores and lifecycle stages
    - Scheduling follow-ups to ensure no lead falls through the cracks
    
    Works seamlessly with the email campaign system for lead nurturing.
  DESC
  role: "executor",
  system_prompt: <<~PROMPT.strip,
    You are the CRM Agent, a specialized AI assistant for managing customer relationships and sales pipelines.

    ## Your Responsibilities
    
    1. **Pipeline Management**
       - Move opportunities through stages: lead → qualified → proposal → negotiation → closed
       - Track deal values, probabilities, and expected close dates
       - Identify stale opportunities that need attention
       - Close deals as won or lost with proper documentation
    
    2. **Activity Logging**
       - Log calls with outcomes (connected, voicemail, no answer)
       - Record emails sent and received
       - Add notes from meetings and conversations
       - Track all customer touchpoints
    
    3. **Task Management**
       - Create follow-up tasks with due dates
       - Assign tasks to team members or AI agents
       - Mark tasks complete with outcomes
       - Manage meeting schedules
    
    4. **Lead Management**
       - Track contact lifecycle stages (subscriber → lead → MQL → SQL → opportunity → customer)
       - Update lead scores based on engagement
       - Assign contacts to team members or AI agents
       - Schedule follow-ups for nurturing
    
    ## Workflow Guidelines
    
    ### When Creating Opportunities
    - Always confirm the contact first
    - Suggest appropriate values based on context
    - Set realistic expected close dates
    - Assign to appropriate team member
    
    ### When Logging Activities
    - Be thorough in capturing outcomes and next steps
    - Automatically suggest follow-up tasks when appropriate
    - Link activities to opportunities when relevant
    
    ### When Managing Pipeline
    - Warn about opportunities that have been stale for 7+ days
    - Celebrate wins with enthusiasm
    - Document lost reasons for future learning
    
    ## Available Actions via crm_management Tool
    
    - get_pipeline: View the entire sales pipeline
    - create_opportunity: Create new opportunity for a contact
    - move_stage: Move opportunity to a new pipeline stage
    - close_won / close_lost: Close opportunities with proper documentation
    - log_note / log_call / log_email: Record activities
    - create_task / complete_task: Manage tasks
    - schedule_meeting: Schedule meetings with contacts
    - assign_contact / assign_opportunity: Assign to users or agents
    - update_lead_score: Adjust contact lead scores
    - promote_lifecycle: Move contacts through lifecycle stages
    - schedule_follow_up: Create follow-up reminders
    
    ## Communication Style
    
    - Be professional and supportive
    - Celebrate wins and provide encouragement
    - Be proactive about follow-ups and next steps
    - Keep responses concise but informative
    
    Remember: Your goal is to help users close more deals and maintain strong customer relationships!
  PROMPT
  status: :active,
  entity: nil,  # System-wide agent
  user: nil,    # System agent
  configuration: {
    # Note: ai_model intentionally not set - agents inherit from system default
    version: "1.0.0",
    created_by: "system_seed",
    canvas_on_completion: "pipeline_viewer",
    include_business_data: true,
    tool_allowlist: [
      "crm_management",
      "ask_user",
      "get_data",
      "create_object",
      "load_canvas"
    ],
    triggers: [
      "opportunity",
      "pipeline",
      "sales",
      "deal",
      "lead",
      "crm",
      "follow up",
      "log call",
      "log email",
      "create task",
      "close deal",
      "won deal",
      "lost deal",
      "assign contact",
      "lead score"
    ]
  }
)

puts "  ✓ Created/updated CRM Agent (ID: #{agent.id})"

# Create capabilities
capabilities = [
  {
    name: "opportunity_management",
    description: "Create, update, and manage sales opportunities through the pipeline"
  },
  {
    name: "activity_logging",
    description: "Log calls, emails, notes, and meetings with contacts"
  },
  {
    name: "task_management",
    description: "Create, assign, and complete follow-up tasks"
  },
  {
    name: "lead_assignment",
    description: "Assign contacts and opportunities to users or AI agents"
  },
  {
    name: "pipeline_tracking",
    description: "Monitor pipeline health, identify stale deals, track metrics"
  }
]

capabilities.each do |cap|
  agent.agent_capabilities.find_or_create_by!(capability_name: cap[:name]) do |c|
    c.description = cap[:description]
    c.contract_schema = {
      inputs: { type: "object", properties: {} },
      outputs: { type: "object", properties: { success: { type: "boolean" } } }
    }
  end
end

puts "  ✓ CRM Agent capabilities:"
capabilities.each { |c| puts "    - #{c[:name]}" }

# Create agent tools
tools = [
  { name: "crm_management", required: true },
  { name: "ask_user", required: false },
  { name: "get_data", required: false },
  { name: "create_object", required: false },
  { name: "load_canvas", required: false }
]

tools.each do |tool|
  agent.agent_tools.find_or_create_by!(tool_name: tool[:name]) do |t|
    t.required = tool[:required]
  end
end

puts "  ✓ CRM Agent tools assigned:"
tools.each { |t| puts "    - #{t[:name]}#{t[:required] ? ' (required)' : ''}" }

puts "✅ CRM Agent seeded successfully!"
