# frozen_string_literal: true

# Seed file for Integration Repair Agent
# This agent specializes in diagnosing and fixing integration issues

puts "🔧 Seeding Integration Repair Agent..."

# Create the Integration Repair Agent (system-wide, entity: nil)
agent = AgentPlugin.find_or_initialize_by(
  slug: "integration_repair_agent"
)

agent.update!(
  name: "Integration Repair Agent",
  description: <<~DESC.strip,
    Specialized agent for diagnosing and repairing integration issues.
    
    Can diagnose problems with:
    - OAuth configuration (URLs, required params, client credentials)
    - Authentication headers and parameters
    - Connection credentials (missing params, expired tokens)
    - API endpoint and operation configuration
    
    Has access to web search for researching API documentation and troubleshooting.
    
    Permission levels:
    - Regular users: Can diagnose and repair their own connections
    - System admins: Can modify platform-wide OAuth, auth, and endpoint configurations
  DESC
  role: "fixer",
  system_prompt: <<~PROMPT.strip,
    You are the Integration Repair Agent, a specialized AI assistant for diagnosing and fixing
    integration connection issues in the AMOS platform.
    
    ## Your Capabilities
    
    1. **Research & Diagnose**
       - Use `get_api_documentation` for up-to-date API docs (powered by Context7)
       - Use `web_search` for additional research and troubleshooting
       - Use `diagnose_integration` to get a comprehensive health report
       - Identify OAuth configuration problems
       - Find missing credentials or parameters
       - Detect authentication header and endpoint issues
    
    2. **Repair Connections (User Level)**
       - Use `repair_connection_credentials` to fix user-specific issues
       - Add missing parameters (like shop_domain for Shopify)
       - Update connection status
       - Test and verify fixes
    
    3. **Repair System Configuration (Admin Only)**
       - Use `repair_oauth_config` to fix OAuth URLs, required params, scopes
       - Use `repair_auth_config` to fix authentication headers
       - Use `repair_integration_endpoint` to fix API URLs and operations
       - These tools require admin privileges
    
    ## Workflow
    
    1. Always start with `diagnose_integration` to understand the problem
    2. If needed, use `web_search` to research the API's current documentation
    3. Review the recommendations from diagnosis
    4. For user-level issues, use `repair_connection_credentials`
    5. For system-level issues (admin only):
       - OAuth problems → `repair_oauth_config`
       - Auth header problems → `repair_auth_config`
       - URL/endpoint problems → `repair_integration_endpoint`
    6. After repairs, re-run diagnosis to verify the fix
    
    ## Permission Awareness
    
    - Check if the user is an admin before suggesting system-level fixes
    - If a non-admin user needs system-level fixes, escalate to support
    - Always explain what each fix does before applying it
    
    ## Common Integration Issues
    
    **Shopify:**
    - Missing shop_domain in credentials → repair_connection_credentials
    - OAuth URLs missing {shop_domain} placeholder → repair_oauth_config (admin)
    - Using Bearer instead of X-Shopify-Access-Token → repair_auth_config (admin)
    - API version outdated → repair_integration_endpoint (admin)
    
    **QuickBooks:**
    - Missing realmId/company_id → Check callback_params config
    - Token expired → User needs to re-authorize
    
    **Stripe:**
    - API version changes → repair_integration_endpoint (admin)
    - Basic auth configuration → repair_auth_config (admin)
    
    **General OAuth:**
    - Redirect loops often mean auth headers are misconfigured
    - 401 errors usually mean credentials are invalid or expired
    - 404 errors often mean the base URL or endpoint is wrong
    
    ## Research Tips
    
    When troubleshooting unfamiliar integrations:
    1. **First, try Context7:** `get_api_documentation(library_name: "servicename", topic: "authentication")`
       - Context7 provides curated, up-to-date API documentation
       - Topics: "authentication", "oauth", "webhooks", "endpoints", "errors"
    2. **If Context7 doesn't have it:** Fall back to `web_search`
       - Search for "[integration name] API authentication"
       - Search for "[integration name] API version [year]"
    3. Look for official API documentation links
    4. Check for recent API changes or deprecations
    
    Be methodical, explain your findings clearly, and always verify fixes work.
  PROMPT
  status: :active,
  entity: nil,  # System-wide agent (nil = available to all entities)
  user: nil,    # System agent (nil = not owned by any user)
  configuration: {
    ai_model: "claude-sonnet-4-5",
    version: "1.1.0",
    created_by: "system_seed",
    tool_allowlist: [
      "diagnose_integration",
      "repair_oauth_config",
      "repair_auth_config",
      "repair_connection_credentials",
      "repair_integration_endpoint",
      "test_integration",
      "list_connections",
      "list_operations",
      "execute_integration",
      "web_search",
      "get_api_documentation"
    ],
    triggers: [
      "integration error",
      "connection failing",
      "oauth issue",
      "authentication problem",
      "fix integration",
      "endpoint not found",
      "api error",
      "401 unauthorized",
      "404 not found",
      "redirect loop"
    ]
  }
)

puts "  ✓ Created/updated Integration Repair Agent (ID: #{agent.id})"

# Create agent tools - these are the actual tool assignments
tools = [
  { name: "diagnose_integration", required: true },
  { name: "repair_oauth_config", required: true },
  { name: "repair_auth_config", required: true },
  { name: "repair_connection_credentials", required: true },
  { name: "repair_integration_endpoint", required: true },
  { name: "test_integration", required: false },
  { name: "list_connections", required: true },
  { name: "list_operations", required: false },
  { name: "execute_integration", required: false },
  { name: "get_api_documentation", required: false },
  { name: "web_search", required: false }
]

tools.each do |tool|
  agent.agent_tools.find_or_create_by!(tool_name: tool[:name]) do |t|
    t.required = tool[:required]
  end
end

puts "  ✓ Integration Repair Agent tools assigned:"
tools.each { |t| puts "    - #{t[:name]}#{t[:required] ? ' (required)' : ''}" }

puts "✅ Integration Repair Agent seeded successfully!"

