# Seed data for SpaceDefinition
#
# Defines the three core spaces: Personal, Work, Team

puts "🌱 Seeding Space Definitions..."

SpaceDefinition.find_or_create_by!(slug: 'personal') do |space|
  space.name = 'Personal'
  space.description = 'Your personal productivity space for life admin, tasks, reminders, and notes.'
  space.icon = 'home'
  space.display_order = 1
  space.enabled = true
  space.context_prompt = <<~PROMPT
    You are in Personal Space - focus on personal productivity, life organization, and individual tasks.
    Help with personal reminders, notes, to-do lists, and life admin tasks.
    This is a more relaxed, personal context - not business-focused.
  PROMPT
  space.default_tool_loadout = %w[
    get_work_inbox
    create_scheduled_task
    list_scheduled_tasks
    manage_scheduled_task
    remember_this
    recall_context
    search_memory
    list_saved
    web_search
    view_web_page
  ]
  space.default_menu_items = %w[
    tasks
    work_items
    reminders
    notes
    documents
  ]
end

SpaceDefinition.find_or_create_by!(slug: 'work') do |space|
  space.name = 'Work'
  space.description = 'Your business workspace for marketing, operations, and automation.'
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
  space.description = 'Collaboration hub for team communication and agent coordination.'
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
