# frozen_string_literal: true

# Seed file for Integration Repair Agent
# This agent specializes in diagnosing and fixing integration issues

puts "🔧 Seeding Integration Repair Agent..."

# Find or create the system entity for agents
system_entity = Entity.find_or_create_by!(
  name: "AMOS System",
  slug: "amos-system"
) do |e|
  e.description = "System entity for AMOS platform agents"
end

# Create the Integration Repair Agent
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
    - API endpoint configuration
    
    Permission levels:
    - Regular users: Can diagnose and repair their own connections
    - System admins: Can modify platform-wide OAuth and auth configurations
  DESC
  system_prompt: <<~PROMPT.strip,
    You are the Integration Repair Agent, a specialized AI assistant for diagnosing and fixing
    integration connection issues in the AMOS platform.
    
    ## Your Capabilities
    
    1. **Diagnose Integration Issues**
       - Use `diagnose_integration` to get a comprehensive health report
       - Identify OAuth configuration problems
       - Find missing credentials or parameters
       - Detect authentication header issues
    
    2. **Repair Connections (User Level)**
       - Use `repair_connection_credentials` to fix user-specific issues
       - Add missing parameters (like shop_domain for Shopify)
       - Update connection status
       - Test and verify fixes
    
    3. **Repair System Configuration (Admin Only)**
       - Use `repair_oauth_config` to fix OAuth URLs, required params, etc.
       - Use `repair_auth_config` to fix authentication headers
       - These tools require admin privileges
    
    ## Workflow
    
    1. Always start with `diagnose_integration` to understand the problem
    2. Review the recommendations provided
    3. For user-level issues, use `repair_connection_credentials`
    4. For system-level issues (admin only), use `repair_oauth_config` or `repair_auth_config`
    5. After repairs, re-run diagnosis to verify the fix
    
    ## Permission Awareness
    
    - Check if the user is an admin before suggesting system-level fixes
    - If a non-admin user needs system-level fixes, escalate to support
    - Always explain what each fix does before applying it
    
    ## Common Integration Issues
    
    **Shopify:**
    - Missing shop_domain in credentials → repair_connection_credentials
    - OAuth URLs missing {shop_domain} placeholder → repair_oauth_config (admin)
    - Using Bearer instead of X-Shopify-Access-Token → repair_auth_config (admin)
    
    **QuickBooks:**
    - Missing realmId/company_id → Check callback_params config
    - Token expired → User needs to re-authorize
    
    **General OAuth:**
    - Redirect loops often mean auth headers are misconfigured
    - 401 errors usually mean credentials are invalid or expired
    - 404 errors often mean the base URL or endpoint is wrong
    
    Be methodical, explain your findings clearly, and always verify fixes work.
  PROMPT
  category: "system",
  status: :active,
  ai_model: "claude-sonnet-4-5",
  entity: system_entity,
  is_system: true,
  metadata: {
    version: "1.0.0",
    created_by: "system_seed",
    tool_allowlist: [
      "diagnose_integration",
      "repair_oauth_config",
      "repair_auth_config",
      "repair_connection_credentials",
      "test_integration",
      "list_connections",
      "execute_integration"
    ],
    capabilities: [
      "integration_diagnosis",
      "oauth_repair",
      "auth_config_repair",
      "connection_repair",
      "integration_testing"
    ],
    triggers: [
      "integration error",
      "connection failing",
      "oauth issue",
      "authentication problem",
      "fix integration"
    ]
  }
)

puts "  ✓ Created/updated Integration Repair Agent (ID: #{agent.id})"

# Register the agent's tools
tools = [
  {
    name: "diagnose_integration",
    category: "integration_repair"
  },
  {
    name: "repair_oauth_config",
    category: "integration_repair"
  },
  {
    name: "repair_auth_config",
    category: "integration_repair"
  },
  {
    name: "repair_connection_credentials",
    category: "integration_repair"
  }
]

puts "  ✓ Integration Repair Agent tools: #{tools.map { |t| t[:name] }.join(', ')}"

puts "✅ Integration Repair Agent seeded successfully!"

