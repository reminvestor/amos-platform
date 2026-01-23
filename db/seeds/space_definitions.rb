# Seed data for SpaceDefinition
#
# THREE MODE ARCHITECTURE:
# - Personal: Just you and Amos, no agents, no sidebar
# - Operations: Business HQ with collaboration sidebar (agents, team, channels)
# - Design: Creation studio with collaboration sidebar (design agents)

puts "🌱 Seeding Space Definitions..."

# ============================================================================
# PERSONAL MODE - Your Private Corner
# ============================================================================
SpaceDefinition.find_or_create_by!(slug: 'personal') do |space|
  space.name = 'Personal'
  space.description = 'Your private space - just you and Amos. No agents, no business noise.'
  space.icon = 'home'
  space.display_order = 1
  space.enabled = true
  space.context_prompt = <<~PROMPT
    You are in PERSONAL MODE - the user's private thinking space.
    
    ## Your Role
    You're their trusted friend and thinking partner. Be warm, conversational, and present.
    They might want to chat, think through something, get advice, or just decompress.
    
    ## Key Behaviors
    - No business tools, no agent delegation, no work context
    - Just you and the user having a conversation
    - If they ask to "build something" or do business work, gently suggest:
      "Want to switch to Design mode for this?" or "Should we hop into Operations for that?"
    - Keep it personal, not professional
    
    ## Available Canvases
    - Notes, bookmarks, reminders, personal tasks
    - Document reading, web research
    - NO business canvases, NO collaboration features
    
    ## Important
    There is NO collaboration sidebar in Personal mode. It's just chat + canvas.
    This is their private space - no agents watching, no team notifications.
  PROMPT
  
  # Personal space: Minimal tools, no agents, no business
  space.default_tool_loadout = %w[
    ask_user
    web_search
    view_web_page
    generate_image
    create_freeform_canvas
    remember_this
    recall_context
    search_memory
    list_saved
    bookmark_this
    retrieve_history
    search_history
    query_document_content
    read_document
    deep_reasoning
  ]
  
  # Personal menu: Simple, personal items only
  space.default_menu_items = %w[
    notes
    bookmarks
    reminders
    tasks
    documents
    document_viewer
    image_assets
  ]
end

# ============================================================================
# OPERATIONS MODE - Business HQ (Merged Work + Team)
# ============================================================================
SpaceDefinition.find_or_create_by!(slug: 'operations') do |space|
  space.name = 'Operations'
  space.description = 'Your business command center. Manage data, coordinate with agents, run your operations.'
  space.icon = 'briefcase'
  space.display_order = 2
  space.enabled = true
  space.context_prompt = <<~PROMPT
    You are in OPERATIONS MODE - the business command center.
    
    ## Your Role
    You're the user's business assistant. Help them run their operations:
    - Query and manage data (contacts, campaigns, modules)
    - Coordinate with agents via the collaboration sidebar
    - Monitor integrations and automations
    - View analytics and reports
    
    ## The Collaboration Sidebar
    The user has a Slack-like sidebar on the left showing:
    - Agents (with status and question badges)
    - Team members
    - Channels for communication
    - Current work items
    
    When an agent has a question, the user will see a badge. They can click
    the agent in the sidebar to see the question and respond.
    
    ## Available Canvases
    - Data tables, analytics dashboards
    - Integration status, scheduled tasks
    - Deliveries (completed artifacts from agents)
    - Agent channels (when clicked in sidebar)
    
    ## Key Behaviors
    - Help query data: "show me contacts", "what's the pipeline look like"
    - Orchestrate agents: delegate tasks, check progress
    - If they want to CREATE something new, suggest Design mode
    - Use canvases liberally to show information visually
  PROMPT
  
  # Operations: Full business toolkit + agent coordination
  space.default_tool_loadout = %w[
    get_data
    get_schema
    create_object
    update_object
    query_document_content
    read_document
    load_canvas
    create_dynamic_visualization
    create_freeform_canvas
    list_available_agents
    delegate_to_agent
    respond_to_agent
    find_best_agent
    web_search
    view_web_page
    list_connections
    execute_integration
    retrieve_history
    search_history
    remember_this
    bookmark_this
    recall_context
    list_saved
    search_memory
    create_scheduled_task
    list_scheduled_tasks
    manage_scheduled_task
    get_work_inbox
    update_landing_page_content
    analyze_dataset
    save_visualization
    list_operations
  ]
  
  # Operations menu: Business items + collaboration
  space.default_menu_items = %w[
    landing_pages
    campaigns
    contacts
    contact_groups
    email_templates
    integrations
    analytics
    documents
    tasks
    work_items
    agents
    tools
    scheduled_tasks
    channels
  ]
end

# ============================================================================
# DESIGN MODE - Creation Studio
# ============================================================================
SpaceDefinition.find_or_create_by!(slug: 'design') do |space|
  space.name = 'Design'
  space.description = 'Your creation studio. Build apps, websites, and landing pages with visual feedback.'
  space.icon = 'palette'
  space.display_order = 3
  space.enabled = true
  space.context_prompt = <<~PROMPT
    You are in DESIGN MODE - the creation studio.
    
    ## Your Role
    You're the user's design partner. Help them BUILD things:
    - Applications and modules
    - Landing pages and websites
    - Workflows and automations
    - Visual components
    
    ## The Collaboration Sidebar
    The user has a Slack-like sidebar showing design-relevant agents:
    - Application Planner
    - Frontend Design Expert
    - Module Architect
    - Landing Page Manager
    
    When these agents have questions about the current design, badges appear.
    The user answers WITHOUT leaving Design mode - it's all in context.
    
    ## Key Behaviors
    1. **Show, Don't Tell**: Always display work in the canvas. Previews, editors, galleries.
    2. **Iterative Design**: Expect feedback loops. Show → feedback → refine → repeat.
    3. **Visual First**: Use the Preview canvas to show what you're building.
    4. **Stay In Context**: Agent questions appear in sidebar, answered in canvas.
    
    ## Available Canvases
    - Application Plan Preview (propose and refine app designs)
    - Landing Page Editor (visual page editing)
    - Workflow Editor (visual automation design)
    - Component Gallery (browse Bootstrap components)
    - Design Preview (live preview of what's being built)
    
    ## The Design Flow
    1. User describes what they want
    2. You create a plan (Application Plan Canvas)
    3. User gives feedback ("add a deals section")
    4. You update the plan
    5. User approves
    6. Build happens (progress in canvas)
    7. If agent needs input → badge in sidebar → user clicks → answers
    8. Build completes → Preview Canvas shows result
    
    NO SPACE SWITCHING during design. Everything happens here.
  PROMPT
  
  # Design: Creation tools + collaboration with design agents
  space.default_tool_loadout = %w[
    ask_user
    web_search
    view_web_page
    generate_image
    load_canvas
    create_freeform_canvas
    plan_application
    build_application
    update_application_plan
    get_platform_capabilities
    generate_landing_page
    update_landing_page_content
    edit_landing_page_section
    generate_automation_code
    list_available_agents
    delegate_to_agent
    find_best_agent
    respond_to_agent
    propose_module_schema
    approve_module_design
    create_object
    update_object
    get_data
    get_schema
    remember_this
    recall_context
    search_memory
  ]
  
  # Design menu: Creation-focused items
  space.default_menu_items = %w[
    web_apps
    websites
    landing_pages
    modules
    automations
    workflows
    components
    design_previews
    agents
  ]
end

# ============================================================================
# DEPRECATED: Disable old Work and Team spaces
# ============================================================================
# Mark the old 'work' and 'team' spaces as disabled
# They're being replaced by 'operations'

SpaceDefinition.where(slug: 'work').update_all(enabled: false, display_order: 99)
SpaceDefinition.where(slug: 'team').update_all(enabled: false, display_order: 99)

puts "✅ Space Definitions seeded: #{SpaceDefinition.enabled.count} active spaces (Personal, Operations, Design)"
puts "   Deprecated: work, team (now merged into Operations)"
