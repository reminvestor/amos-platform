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

puts "✅ Space Definitions seeded: #{SpaceDefinition.count} spaces"
