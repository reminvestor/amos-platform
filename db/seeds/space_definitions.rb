# Seed data for SpaceDefinition
#
# Defines the three core spaces: Personal, Work, Team

puts "🌱 Seeding Space Definitions..."

SpaceDefinition.find_or_create_by!(slug: 'personal') do |space|
  space.name = 'Personal'
  space.description = 'Your personal space - a trusted companion for anything on your mind.'
  space.icon = 'home'
  space.display_order = 1
  space.enabled = true
  space.context_prompt = <<~PROMPT
    This is Personal Space - the user has switched here because they want a different vibe.
    You're their trusted friend who happens to understand their business context.
    Be warm, conversational, and let them guide where things go.
    They might want to chat, think through something, get advice, or just decompress.
    Don't assume they want to "work on" something - just be present and helpful.
  PROMPT
  # Personal space tools: Conversation, research, memory, personal productivity
  # EXCLUDED: Campaigns, landing pages, integrations, business analytics, module building
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
    create_scheduled_task
    list_scheduled_tasks
    manage_scheduled_task
    get_work_inbox
    list_available_agents
    delegate_to_agent
    find_best_agent
    deep_reasoning
  ]
  # Personal space menu: Personal productivity, no business items
  space.default_menu_items = %w[
    notes
    bookmarks
    reminders
    tasks
    work_inbox
    documents
    document_viewer
    image_assets
  ]
end

SpaceDefinition.find_or_create_by!(slug: 'work') do |space|
  space.name = 'Work'
  space.description = 'A focused view for business operations, marketing tools, and professional workflows.'
  space.icon = 'briefcase'
  space.display_order = 2
  space.enabled = true
  space.context_prompt = <<~PROMPT
    You are in Work Space - focus on business automation, marketing, content creation, and professional workflows.
    Help with landing pages, email campaigns, contacts, integrations, analytics, and business operations.
    This is the primary business context with full access to marketing and automation tools.
  PROMPT
  space.default_tool_loadout = %w[
    get_data
    get_schema
    query_document_content
    read_document
    load_canvas
    create_dynamic_visualization
    create_freeform_canvas
    list_available_agents
    delegate_to_agent
    respond_to_agent
    web_search
    view_web_page
    list_connections
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
    create_object
    update_object
    update_landing_page_content
    execute_integration
    analyze_dataset
    save_visualization
    list_operations
  ]
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
  ]
end

SpaceDefinition.find_or_create_by!(slug: 'team') do |space|
  space.name = 'Team'
  space.description = 'Your main hub for interacting with agents, delegating work, and collaborating with AI and humans.'
  space.icon = 'users'
  space.display_order = 3
  space.enabled = true
  space.context_prompt = <<~PROMPT
    You are in Team Space - focus on collaboration, team coordination, and shared visibility of agent work.
    Help coordinate between team members and AI agents, manage shared tasks, and facilitate team communication.
    Show agent delegations, task progress, and team notifications.
  PROMPT
  space.default_tool_loadout = %w[
    list_available_agents
    delegate_to_agent
    respond_to_agent
    get_work_inbox
    search_history
    list_connections
    remember_this
    recall_context
    list_saved
    search_memory
    create_scheduled_task
    list_scheduled_tasks
  ]
  space.default_menu_items = %w[
    team_channels
    agents
    shared_tasks
    work_items
    notifications
    integrations
  ]
end

SpaceDefinition.find_or_create_by!(slug: 'design') do |space|
  space.name = 'Design'
  space.description = 'Build and design web apps, websites, landing pages with visual feedback and AI assistance.'
  space.icon = 'palette'
  space.display_order = 4
  space.enabled = true
  space.context_prompt = <<~PROMPT
    You are in DESIGN SPACE - the creative studio for building web applications, websites, and landing pages.

    ## Your Role
    You are Amos in "designer mode" - still the same helpful assistant, but now focused on helping
    users BUILD things visually. You have access to specialized design and building tools.

    ## Key Behaviors
    1. **Show, Don't Tell**: Always display work in the canvas. Load previews, show designs, display workflows.
    2. **Iterative Design**: Expect feedback loops. Users will see the canvas and ask for changes.
    3. **Visual Feedback**: When building, show progress in real-time via the canvas.
    4. **Delegate Wisely**: Use specialized agents (Frontend Design Expert, Platform Factory) for complex tasks.

    ## Available Canvases
    - **Web App Preview**: iFrame showing the live web app for testing
    - **Landing Page Editor**: Visual editor for landing pages
    - **Workflow Editor**: Visual diagram of automations and workflows
    - **Component Gallery**: Browse and customize Bootstrap components
    - **Design Preview**: Show proposed designs before building

    ## Design Principles
    - Bootstrap 5 first - all components use Bootstrap classes
    - Mobile responsive by default
    - Beautiful by default - not generic AI slop
    - Fast iteration - show changes immediately

    ## When User Asks to Build Something
    1. Clarify requirements (quick questions, not lengthy interviews)
    2. Show a design preview in the canvas
    3. Get feedback and iterate
    4. Build when approved
    5. Show the result in the preview canvas

    ## Important
    - The canvas is your primary output - USE IT constantly
    - Users can see and interact with what you build
    - They can click, type, and test in the preview
    - Listen to their feedback on what they see
  PROMPT
  
  # Design space tools: Building, designing, previewing
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
  
  # Design space menu: Building and design focused
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

puts "✅ Space Definitions seeded: #{SpaceDefinition.count} spaces"
