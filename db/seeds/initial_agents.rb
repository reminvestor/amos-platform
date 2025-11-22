# Seed basic agent plugins for the new architecture

# Ensure we have basic tool definitions first
puts "Seeding Tool Definitions..."

# AskUser Tool
ToolDefinition.find_or_create_by!(name: "ask_user") do |tool|
  tool.description = "Ask the user for input or clarification during execution"
  tool.execution_type = "ruby_code"
  tool.parameters = {
    "type" => "object",
    "properties" => {
      "question" => { "type" => "string", "description" => "The question to ask the user" },
      "options" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Optional list of valid choices" }
    },
    "required" => ["question"]
  }
  tool.code = <<~RUBY
    # This is handled by the AskUserTool service class
    # We just register the definition here
  RUBY
  tool.admin_only = false
end

# Web Search Tool (Placeholder)
ToolDefinition.find_or_create_by!(name: "web_search") do |tool|
  tool.description = "Search the web for information"
  tool.execution_type = "ruby_code"
  tool.parameters = {
    "type" => "object",
    "properties" => {
      "query" => { "type" => "string", "description" => "Search query" }
    },
    "required" => ["query"]
  }
  tool.code = "result = { results: [] }" # Placeholder
  tool.admin_only = false
end

puts "Seeding Agent Plugins..."

# 1. Orchestrator Agent (Dispatcher)
AgentPlugin.find_or_create_by!(slug: "orchestrator_agent") do |agent|
  agent.name = "Orchestrator Agent"
  agent.role = "planner"
  agent.status = "active"
  agent.description = "Primary agent responsible for analyzing user requests and delegating tasks to specialized agents."
  agent.version = "1.0.0"
  agent.priority = 100
  agent.system_prompt = {
    "prompt" => "You are the Orchestrator. Your job is to analyze the user's request and decide which specialized agent should handle it. You do not execute tasks yourself; you delegate them."
  }
  agent.capabilities_definition = {
    "planning" => "Can break down complex tasks",
    "delegation" => "Can assign tasks to other agents"
  }
end

# 2. AI Landing Page Creator
landing_page_agent = AgentPlugin.find_or_create_by!(slug: "landing_page_creator") do |agent|
  agent.name = "AI Landing Page Creator"
  agent.role = "executor"
  agent.status = "active"
  agent.description = "Specialized agent for generating high-conversion landing pages based on user requirements."
  agent.version = "1.0.0"
  agent.priority = 90
  agent.execution_strategy = "standard"
  agent.configuration = {
    "canvas_on_completion" => "landing_page_preview",
    "include_business_data" => true
  }
  agent.system_prompt = {
    "prompt" => "You are an expert Landing Page Creator. You design and generate HTML/CSS for landing pages. Always ask the user for their business name and target audience if not provided."
  }
  agent.capabilities_definition = {
    "web_design" => "Can generate HTML/CSS layouts",
    "copywriting" => "Can write marketing copy"
  }
end

# Add tools to Landing Page Creator
landing_page_agent.agent_tools.find_or_create_by!(tool_name: "ask_user") do |at|
  at.description = "Ask user for design preferences"
  at.required = true
end

# 3. Research Assistant
research_agent = AgentPlugin.find_or_create_by!(slug: "research_assistant") do |agent|
  agent.name = "Research Assistant"
  agent.role = "analyst"
  agent.status = "active"
  agent.description = "Agent responsible for gathering information from the web and summarizing findings."
  agent.version = "1.0.0"
  agent.priority = 80
  agent.execution_strategy = "standard"
  agent.system_prompt = {
    "prompt" => "You are a Research Assistant. Use the web search tool to find information and summarize it clearly."
  }
  agent.capabilities_definition = {
    "research" => "Can find info on the web",
    "summarization" => "Can condense large texts"
  }
end

research_agent.agent_tools.find_or_create_by!(tool_name: "web_search")

# 4. Data Analyst
AgentPlugin.find_or_create_by!(slug: "data_analyst") do |agent|
  agent.name = "Data Analyst"
  agent.role = "analyst"
  agent.status = "active"
  agent.description = "Agent for analyzing business data and generating insights."
  agent.version = "1.0.0"
  agent.priority = 85
  agent.execution_strategy = "standard"
  agent.configuration = {
    "include_business_data" => true
  }
  agent.system_prompt = {
    "prompt" => "You are a Data Analyst. Analyze the provided business data and identify trends and opportunities."
  }
end

puts "Agents seeded successfully!"

# Force update embeddings for all active agents
puts "Updating vector embeddings..."
AgentPlugin.active.find_each do |agent|
  puts "Vectorizing #{agent.name}..."
  agent.send(:update_embedding)
end

puts "Done."

