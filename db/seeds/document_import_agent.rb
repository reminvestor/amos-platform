# frozen_string_literal: true

# Seed file for Document Import Agent
# This agent specializes in importing data from CSV files, external integrations, and other sources

puts "📥 Seeding Document Import Agent..."

# Create the Document Import Agent (system-wide, entity: nil)
agent = AgentPlugin.find_or_initialize_by(
  slug: "document_import_agent"
)

agent.update!(
  name: "Document Import Agent",
  description: <<~DESC.strip,
    Imports data from various sources into the platform.
    
    Supported sources:
    • CSV/Excel files - Parse and import spreadsheet data
    • External Integrations - Pull data from connected apps (Stripe, HubSpot, etc.)
    • API responses - Import structured JSON/XML data
    
    Target destinations:
    • Contacts - Import customer/lead lists
    • Campaigns - Import campaign configurations
    • Custom Modules - Import into any user-created module
    
    Use this agent when users ask to:
    - Upload a CSV and create contacts
    - Import data from an external app
    - Pull records from an integration
    - Migrate data into the system
    - Sync data from another platform
  DESC
  role: "executor",
  system_prompt: <<~PROMPT.strip,
    You are a Data Import specialist. Your job is to help users import data from various sources into the platform.
    
    ## Your Capabilities
    
    1. **CSV/File Import** - Parse and import spreadsheet data
       - Use `parse_csv` to read and analyze CSV files
       - Use `bulk_import` to create records from parsed data
       - Can handle contacts, campaigns, and custom modules
       
    2. **Integration Import** - Pull data from connected apps
       - Use `list_connections` to see available integrations
       - Use `list_operations` to find data retrieval operations
       - Use `execute_integration` to fetch data
       - Use `bulk_import` to import the fetched data
       
    3. **Data Mapping** - Help users map their fields to system fields
       - Analyze source data structure
       - Suggest field mappings
       - Handle field transformations
    
    ## Workflow for CSV Import
    
    1. **Parse the file**
       - Use `parse_csv` with source='upload' and the filename
       - Review the field_analysis to understand the data
       - Check suggested_object_types for import destination
       
    2. **Confirm with user**
       - Show them a preview of the data
       - Ask which object type to import as (contacts, campaigns, or a module)
       - Confirm field mappings if names don't match exactly
       
    3. **Import the data**
       - Use `bulk_import` with the parsed records
       - Apply any field_mapping needed
       - Consider using dry_run=true first for large imports
       
    4. **Report results**
       - Tell user how many records were created/updated/skipped
       - Highlight any errors that occurred
    
    ## Workflow for Integration Import
    
    1. **Check available integrations**
       - Use `list_connections` to see what's connected
       - Use `list_operations` to find data retrieval operations
       
    2. **Fetch the data**
       - Use `execute_integration` to pull data from the external system
       - Parse the response to extract records
       
    3. **Transform if needed**
       - Map external field names to internal field names
       - Handle data type conversions
       
    4. **Import the data**
       - Use `bulk_import` with appropriate field_mapping
       - Report results to user
    
    ## Working with Integration Agents
    
    If the import requires complex integration work (e.g., custom API queries, pagination handling):
    - Use `ask_agent_for_help` to delegate to the appropriate Integration Agent
    - For example: "Ask the Stripe Agent to pull all customers from the last 30 days"
    - The integration agent can handle the complexities, you handle the import
    
    ## Field Mapping Tips
    
    Common mappings for contacts:
    - "Email Address" → "email"
    - "Full Name" / "Name" → "name"
    - "First Name" + "Last Name" → combine into "name"
    - "Phone Number" / "Mobile" → "phone"
    - "Company" / "Organization" → "company"
    
    ## Error Handling
    
    - Use `skip_validation=true` to import valid records even if some fail
    - Use `update_existing=true` to update records instead of creating duplicates
    - Always report errors to the user with specific row numbers
    - Suggest fixes for common issues (missing required fields, invalid formats)
    
    ## Important Notes
    
    - Always preview data before bulk importing
    - For imports > 100 rows, recommend a dry run first
    - Be explicit about what will happen before doing destructive operations
    - The bulk_import tool has a 500 record limit per batch
    - For very large imports, guide the user to split into multiple batches
  PROMPT
  status: :active,
  entity: nil,  # System-wide agent
  configuration: {
    version: "1.0.0",
    created_by: "system_seed",
    max_retries: 2,
    timeout_seconds: 180,
    model: "claude-sonnet-4-20250514",
    icon: "file-input",
    color: "#8b5cf6",
    category: "productivity",
    tool_allowlist: [
      "parse_csv",
      "bulk_import",
      "list_connections",
      "list_operations",
      "execute_integration",
      "query_document_content",
      "read_document",
      "list_documents",
      "get_data",
      "ask_user",
      "ask_agent_for_help",
      "load_dm_canvas"
    ],
    triggers: [
      "import",
      "upload csv",
      "import csv",
      "import contacts",
      "upload spreadsheet",
      "import from",
      "pull from",
      "sync from",
      "migrate",
      "bring in",
      "load data",
      "import data",
      "csv upload",
      "bulk import",
      "mass import",
      "import from stripe",
      "import from hubspot",
      "pull contacts from"
    ]
  }
)

puts "  ✓ Created/updated Document Import Agent (ID: #{agent.id})"

# Create capabilities
capabilities = [
  {
    capability_name: "csv_import",
    contract_schema: {
      description: "Import data from a CSV file",
      inputs: [
        { name: "file", type: "string", required: true, description: "Filename or file identifier" },
        { name: "object_type", type: "string", required: true, description: "Target object type (contacts, campaigns, or module slug)" },
        { name: "field_mapping", type: "object", required: false, description: "Optional field name mappings" }
      ],
      outputs: [
        { name: "created", type: "integer", description: "Number of records created" },
        { name: "updated", type: "integer", description: "Number of records updated" },
        { name: "errors", type: "array", description: "Any errors encountered" }
      ]
    }
  },
  {
    capability_name: "integration_import",
    contract_schema: {
      description: "Import data from a connected integration",
      inputs: [
        { name: "integration", type: "string", required: true, description: "Integration name (e.g., 'stripe', 'hubspot')" },
        { name: "operation", type: "string", required: true, description: "Operation to fetch data (e.g., 'list_customers')" },
        { name: "object_type", type: "string", required: true, description: "Target object type for import" }
      ],
      outputs: [
        { name: "fetched", type: "integer", description: "Number of records fetched from integration" },
        { name: "imported", type: "integer", description: "Number of records imported" }
      ]
    }
  },
  {
    capability_name: "data_preview",
    contract_schema: {
      description: "Preview and analyze data before import",
      inputs: [
        { name: "source", type: "string", required: true, description: "Data source (file, integration, etc.)" }
      ],
      outputs: [
        { name: "columns", type: "array", description: "Detected columns" },
        { name: "row_count", type: "integer", description: "Total rows" },
        { name: "suggested_mappings", type: "object", description: "Suggested field mappings" }
      ]
    }
  }
]

# Clear and recreate capabilities
agent.agent_capabilities.destroy_all
capabilities.each do |cap_data|
  agent.agent_capabilities.create!(cap_data)
end

puts "  ✓ Document Import Agent capabilities:"
capabilities.each { |c| puts "    - #{c[:capability_name]}" }

# Create agent tools
tools = [
  # Core import tools
  { name: "parse_csv", required: true },
  { name: "bulk_import", required: true },
  # Integration access
  { name: "list_connections", required: false },
  { name: "list_operations", required: false },
  { name: "execute_integration", required: false },
  # Document access
  { name: "query_document_content", required: false },
  { name: "read_document", required: false },
  { name: "list_documents", required: false },
  # Data access
  { name: "get_data", required: false },
  # User interaction
  { name: "ask_user", required: false },
  # Agent collaboration
  { name: "ask_agent_for_help", required: false },
  # Canvas for previews
  { name: "load_dm_canvas", required: false }
]

tools.each do |tool|
  agent.agent_tools.find_or_create_by!(tool_name: tool[:name]) do |t|
    t.required = tool[:required]
  end
end

puts "  ✓ Document Import Agent tools assigned:"
tools.each { |t| puts "    - #{t[:name]}#{t[:required] ? ' (required)' : ''}" }

puts "✅ Document Import Agent seeding complete!"

