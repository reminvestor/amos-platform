# frozen_string_literal: true

# Seed file for Document Export Agent
# This agent specializes in generating documents in various formats (CSV, Excel, PDF)

puts "📄 Seeding Document Export Agent..."

# Create the Document Export Agent (system-wide, entity: nil)
agent = AgentPlugin.find_or_initialize_by(
  slug: "document_export_agent"
)

agent.update!(
  name: "Document Export Agent",
  description: <<~DESC.strip,
    Generates documents and exports data in various formats.
    
    Supported formats:
    • CSV - Simple spreadsheet data
    • Excel (.xlsx) - Formatted spreadsheets with multiple sheets
    • PDF - Professional reports and documents
    
    Use this agent when users ask to:
    - Export data as CSV/Excel/PDF
    - Generate a report
    - Download data in a specific format
    - Create a printable document
    
    The agent creates work items with downloadable attachments.
  DESC
  role: "executor",
  system_prompt: <<~PROMPT.strip,
    You are a Document Export specialist. Your job is to generate documents in the user's requested format.
    
    ## Your Capabilities
    
    1. **CSV Export** - Use `generate_csv` for simple spreadsheet data
       - Best for: Raw data, imports into other systems, simple lists
       
    2. **Excel Export** - Use `generate_excel` for formatted spreadsheets
       - Best for: Data with formatting needs, multiple sheets, business reports
       - Supports: Multiple worksheets, auto-formatted headers, styled tables
       
    3. **PDF Generation** - Use `generate_pdf` for professional documents
       - Best for: Reports, printable documents, presentations
       - Supports: Titles, sections, tables, formatted text
    
    ## Data Sources - Where to Get Data
    
    You can pull data from multiple sources:
    
    1. **Integrations** (Stripe, QuickBooks, etc.)
       - Use `list_connections` to see available integrations
       - Use `list_operations` to see what data you can pull
       - Use `execute_integration` to fetch the actual data
       - Example: "Last 10 Stripe customers" → execute_integration(stripe, list_customers)
    
    2. **Uploaded Documents** (PDFs, etc.)
       - Use `query_document_content` to search/read document content
       - Use `read_document` to get full document text
       - Example: "Export data from the uploaded PDF" → query_document_content first
    
    3. **System Data**
       - Use `get_data` to query campaigns, contacts, landing pages, etc.
       - Example: "Export my contacts" → get_data(contacts)
    
    4. **User-Provided Data**
       - Data may be provided directly in the chat/request
       - Parse and structure it for export
    
    ## Workflow
    
    1. Analyze the user's request to determine:
       - What data they want exported
       - WHERE the data comes from (integration? document? system? chat?)
       - What format they need (CSV, Excel, PDF)
    
    2. Fetch the data from the appropriate source
    
    3. Generate the document using the appropriate tool
    
    4. Confirm completion - the file will be available in their Work Items
    
    ## Format Selection Guidelines
    
    - "Give me a CSV" or "export to spreadsheet" → `generate_csv`
    - "Create an Excel file" or "formatted spreadsheet" → `generate_excel`
    - "Generate a PDF" or "create a report" or "printable" → `generate_pdf`
    - Default for data exports → CSV (simplest)
    - Default for reports → PDF (professional look)
    
    ## Important Notes
    
    - Always give the export a clear, descriptive title
    - Include relevant metadata in the description
    - The generated file will automatically be added to the user's Work Items
    - Users can download from there or access the direct download URL
  PROMPT
  status: :active,
  entity: nil,  # System-wide agent
  configuration: {
    version: "1.0.0",
    created_by: "system_seed",
    max_retries: 2,
    timeout_seconds: 120,
    model: "claude-sonnet-4-20250514",
    icon: "file-output",
    color: "#10b981",
    category: "productivity",
    tool_allowlist: [
      "generate_csv",
      "generate_excel",
      "generate_pdf",
      "list_connections",
      "list_operations",
      "execute_integration",
      "query_document_content",
      "read_document",
      "get_data",
      "ask_user"
    ],
    triggers: [
      "export",
      "csv",
      "excel",
      "xlsx",
      "pdf",
      "report",
      "document",
      "download",
      "spreadsheet",
      "generate",
      "create document",
      "export as",
      "give me a csv",
      "create excel",
      "generate pdf"
    ]
  }
)

puts "  ✓ Created/updated Document Export Agent (ID: #{agent.id})"

# Create capabilities
capabilities = [
  {
    capability_name: "csv_export",
    contract_schema: {
      description: "Export data to CSV format",
      inputs: [
        { name: "data", type: "array", required: true, description: "Array of data objects to export" },
        { name: "title", type: "string", required: true, description: "Name for the export file" },
        { name: "headers", type: "array", required: false, description: "Optional column headers" }
      ],
      outputs: [
        { name: "download_url", type: "string", description: "URL to download the file" },
        { name: "row_count", type: "integer", description: "Number of rows exported" }
      ]
    }
  },
  {
    capability_name: "excel_export",
    contract_schema: {
      description: "Export data to Excel (.xlsx) format",
      inputs: [
        { name: "data", type: "array", required: true, description: "Data for single sheet, or use sheets param for multiple" },
        { name: "sheets", type: "array", required: false, description: "Multiple sheet definitions" },
        { name: "title", type: "string", required: true, description: "Name for the export file" }
      ],
      outputs: [
        { name: "download_url", type: "string", description: "URL to download the file" },
        { name: "sheet_count", type: "integer", description: "Number of sheets created" }
      ]
    }
  },
  {
    capability_name: "pdf_generation",
    contract_schema: {
      description: "Generate a PDF document",
      inputs: [
        { name: "title", type: "string", required: true, description: "Document title" },
        { name: "content", type: "string", required: false, description: "Main body content" },
        { name: "sections", type: "array", required: false, description: "Structured sections" },
        { name: "data", type: "array", required: false, description: "Data table to include" }
      ],
      outputs: [
        { name: "download_url", type: "string", description: "URL to download the file" }
      ]
    }
  }
]

# Clear and recreate capabilities
agent.agent_capabilities.destroy_all
capabilities.each do |cap_data|
  agent.agent_capabilities.create!(cap_data)
end

puts "  ✓ Document Export Agent capabilities:"
capabilities.each { |c| puts "    - #{c[:capability_name]}" }

# Create agent tools - these are the actual tool assignments
# The agent needs access to various data sources:
# - Integrations (Stripe, etc.) for pulling live data
# - Documents for reading uploaded files
# - get_data for querying the system
tools = [
  # Core export tools
  { name: "generate_csv", required: true },
  { name: "generate_excel", required: true },
  { name: "generate_pdf", required: true },
  # Integration access (to pull data from Stripe, etc.)
  { name: "list_connections", required: false },
  { name: "list_operations", required: false },
  { name: "execute_integration", required: false },
  # Document access (to read uploaded PDFs, etc.)
  { name: "query_document_content", required: false },
  { name: "read_document", required: false },
  # Data access
  { name: "get_data", required: false },
  # User interaction
  { name: "ask_user", required: false }
]

tools.each do |tool|
  agent.agent_tools.find_or_create_by!(tool_name: tool[:name]) do |t|
    t.required = tool[:required]
  end
end

puts "  ✓ Document Export Agent tools assigned:"
tools.each { |t| puts "    - #{t[:name]}#{t[:required] ? ' (required)' : ''}" }

puts "✅ Document Export Agent seeding complete!"
