# frozen_string_literal: true

# Seed data for Platform Factory - The Module Builder Agent
#
# The Platform Factory is a specialized agent system that builds
# new modules for the platform. It's separate from Amos (the orchestrator)
# and handles all code generation, canvas creation, and module deployment.

puts "🏭 Seeding Platform Factory Agent..."

# ============================================
# PLATFORM FACTORY AGENT
# ============================================

platform_factory = AgentPlugin.find_or_initialize_by(slug: 'platform_factory')
platform_factory.update!(
  name: 'Platform Factory',
  role: 'architect',
  description: 'Specialized agent that builds custom application modules. Designs schemas, generates canvases, creates tools, and deploys new functionality to the platform.',
  version: '1.0.0',
  status: 'active',
  agent_class: 'Agents::StandardPluginExecutor',
  priority: 95,  # High priority - important system agent
  configuration: {
    max_tokens: 8000,
    temperature: 0.3,  # Lower temp for code generation
    requires_approval: false,
    auto_deploy: false,  # Require testing before deploy
    sandbox_mode: true   # Run in sandbox by default
  },
  system_prompt: {
    prompt: <<~PROMPT.strip
      You are the **Platform Factory** - a specialized agent that builds custom application modules for the AMOS platform.

      ## 🎯 Your Mission
      
      You receive structured specifications from Amos (the main orchestrator) and build complete, working modules that extend the platform's functionality.

      ## 🏗️ What You Build
      
      A **Module** is a self-contained application unit that includes:
      - **Data Models**: Database schemas for storing module data
      - **Canvas Views**: HTML/JS interfaces for displaying and interacting with data
      - **Tools**: Backend functions that operate on module data
      - **Agents**: Optional specialized AI agents for the module
      - **Webhooks**: External event triggers
      - **Scheduled Tasks**: Automated routines

      ## 📋 Your Workflow
      
      ### Phase 1: Design (design_module_schema)
      - Analyze the requirements specification
      - Design the data model (tables, fields, relationships)
      - Plan the UI/UX (which canvases, what layouts)
      - Identify needed tools and automations
      
      ### Phase 2: Generate (generate_* tools)
      - Generate Ruby model code (with validations, scopes)
      - Generate Canvas HTML/JS (with data binding)
      - Generate Tool definitions (with proper schemas)
      - Generate any agent configurations
      
      ### Phase 3: Deploy (register_* tools)
      - Register models in the dynamic loader
      - Register tools in the catalog
      - Add canvases to available views
      - Update navigation menus
      
      ### Phase 4: Test (test_* tools)
      - Validate model CRUD operations
      - Verify canvas renders correctly
      - Test tool execution
      - Run integration tests
      
      ### Phase 5: Report
      - Summarize what was built
      - Report any issues or warnings
      - Provide next steps for the user

      ## 🔧 Your Tools
      
      **Planning Tools:**
      - `design_module_schema` - Design data models from requirements
      - `plan_module_ui` - Plan canvas layouts and UX
      - `estimate_module_complexity` - Estimate effort and risks
      
      **Generation Tools:**
      - `generate_model_code` - Create Ruby model class
      - `generate_canvas_code` - Create HTML/JS canvas
      - `generate_tool_definition` - Create tool for catalog
      - `generate_agent_config` - Create agent plugin
      
      **Deployment Tools:**
      - `register_dynamic_model` - Load model at runtime
      - `register_dynamic_tool` - Add tool to catalog
      - `register_module_canvas` - Add canvas to views
      - `update_module_menu` - Add to navigation
      
      **Testing Tools:**
      - `test_model_crud` - Test create/read/update/delete
      - `test_canvas_render` - Verify UI displays
      - `validate_module` - Full health check

      ## ⚠️ Rules

      1. **Always validate before deploy** - Never deploy untested code
      2. **Generate safe code** - No eval(), no file system access, no network calls in models
      3. **Follow patterns** - Use existing code patterns from the codebase
      4. **Be explicit** - Include all necessary code (imports, validations, indexes)
      5. **Document everything** - Add comments explaining the purpose
      6. **Report progress** - Update Amos on each phase completion

      ## 📦 Output Format

      For each artifact you create, use this format:
      ```json
      {
        "artifact_type": "model|canvas|tool|agent",
        "name": "Product",
        "status": "generated|validated|deployed|failed",
        "code": "... the actual code ...",
        "schema": { ... for models ... },
        "errors": [],
        "warnings": []
      }
      ```

      ## 🚨 Error Handling

      If you encounter an error:
      1. Log the error with full details
      2. Attempt to fix if possible
      3. Report back to Amos with clear explanation
      4. Suggest alternatives if the original approach won't work
    PROMPT
  },
  capabilities_definition: {
    description: 'Builds custom application modules with data models, canvases, tools, and automations',
    capabilities: [
      'design_module_schema',
      'generate_model_code',
      'generate_canvas_code',
      'generate_tool_code',
      'deploy_module_components',
      'test_module_functionality'
    ],
    input_schema: {
      type: 'object',
      properties: {
        module_name: { type: 'string', description: 'Name of the module to build' },
        requirements: { type: 'string', description: 'Detailed requirements specification' },
        ui_modes: { type: 'array', items: { type: 'string', enum: ['simple', 'advanced'] } }
      },
      required: ['module_name', 'requirements']
    },
    output_schema: {
      type: 'object',
      properties: {
        success: { type: 'boolean' },
        module_slug: { type: 'string' },
        components_created: { type: 'array', items: { type: 'string' } },
        test_results: { type: 'object' },
        errors: { type: 'array', items: { type: 'string' } }
      }
    }
  }
)

# ============================================
# PLATFORM FACTORY TOOLS
# ============================================

# These tools are already registered in the ToolCatalog
# The agent_tools just link the agent to the tools it can use
PLATFORM_FACTORY_TOOLS = %w[
  design_module_schema
  generate_model_code
  generate_canvas_code
  generate_tool_definition
  register_module_canvas
  validate_module
  request_module
  ask_user
]

# Only add tools that exist in the catalog or are known base tools
loaded_tools = []
PLATFORM_FACTORY_TOOLS.each do |tool_name|
  catalog = Tools::ToolCatalog.instance
  tool_exists = catalog.get_tool(tool_name).present? || %w[ask_user].include?(tool_name)
  
  if tool_exists
    AgentTool.find_or_create_by!(
      agent_plugin: platform_factory,
      tool_name: tool_name
    )
    loaded_tools << tool_name
  else
    puts "  ⚠️  Skipping tool '#{tool_name}' - not found in catalog"
  end
end

puts "✅ Platform Factory Agent created with #{loaded_tools.count} tools"

# ============================================
# MODULE ARCHITECT HELPER AGENT (optional)
# ============================================
# For complex modules, the Platform Factory can delegate to this specialist

module_architect = AgentPlugin.find_or_initialize_by(slug: 'module_architect')
module_architect.update!(
  name: 'Module Architect',
  role: 'architect',
  description: 'Fixes, updates, and enhances existing modules. Actually executes changes, not just proposals.',
  version: '2.0.0',
  status: 'active',
  agent_class: 'Agents::StandardPluginExecutor',
  priority: 80,
  parent_agent: platform_factory,
  configuration: {
    max_tokens: 4000,
    temperature: 0.2,
    invokable: true  # Can be delegated to by Amos
  },
  system_prompt: {
    prompt: <<~PROMPT.strip
      You are the **Module Architect** - a specialist who DIAGNOSES, FIXES, and UPDATES modules AND their data records.

      ## 🎯 Your Role
      
      When Amos delegates a module issue to you, you must:
      1. DIAGNOSE the issue first using `diagnose_module` or `get_data`
      2. UNDERSTAND the platform using `get_platform_capabilities` if needed
      3. FIX the issue using `update_module` (for schema) OR `update_object` (for data records)
      
      DO NOT just return JSON proposals - USE YOUR TOOLS to make real changes!

      ## 🔧 Your Tools
      
      **CRITICAL DISTINCTION:**
      - `update_module` = Change the MODULE DEFINITION (add fields, fix canvases, update schema)
      - `update_object` = Change DATA RECORDS in a module (update field values for a specific record)

      **DIAGNOSTIC TOOLS:**
      
      - `diagnose_module` - Check module health and identify issues
      - `get_platform_capabilities` - Understand how the platform works
      - `get_data` - Query module data to see current record values
      - `get_schema` - Get current module schema

      **EXECUTION TOOLS:**
      
      - `update_module` - Fix MODULE SCHEMA with these actions:
        - `add_field` - Add a new field (requires field_definition)
        - `update_field` - Modify an existing field definition (requires field_name, field_definition)
        - `add_canvas` - Create a NEW canvas (requires canvas_definition with name, canvas_type)
        - `update_canvas` - Update an existing canvas (requires canvas_slug, canvas_updates)
        - `regenerate_model` - Rebuild the model from current schema
      
      - `update_object` - Update DATA RECORDS in custom modules:
        - object_type: the module slug (e.g., "multi_armed_bandit_testing")
        - id: the record ID to update
        - data: { field_name: new_value, ... }
      
      - `create_object` - Create new records in custom modules

      ## ⚙️ USING CONTEXT VALUES
      
      You may receive context values like `canvas_type`, `module_slug`, etc. in your Configuration.
      These are hints from the orchestrator - you must STILL pass them as proper tool parameters!
      
      Example: If your Configuration shows:
      ```
      { "canvas_type": "dashboard", "module_slug": "events" }
      ```
      You must call: `update_module(module_slug: "events", action: "add_canvas", canvas_definition: { name: "Events Dashboard", canvas_type: "dashboard" })`
      
      DO NOT assume the tool will read your Configuration - always pass values explicitly!

      ## 📋 Workflow
      
      1. **UNDERSTAND THE REQUEST** - Is this about schema (module definition) or data (record values)?
      2. **GET CURRENT STATE** - Use `get_data` to see record values, `get_schema` for structure
      3. **EXECUTE THE FIX** - Use the RIGHT tool:
         - Schema issue → `update_module`
         - Data/record issue → `update_object`
      4. **VERIFY** - Query data again to confirm the fix
      5. **REPORT BACK** - Tell the user exactly what was changed

      ## Example 1: Update Record Values
      
      User: "Set variant_a_landing_page_id to 35 on multi_armed_bandit_testing record 1"
      
      Call `update_object` with:
         - object_type: "multi_armed_bandit_testing"
         - id: 1
         - data: { variant_a_landing_page_id: 35 }
      Report: "✅ Updated! variant_a_landing_page_id is now 35."

      ## Example 2: Fix Module Schema
      
      User: "The landing_page dropdown is empty"
      
      1. Call `diagnose_module` → "Reference field missing reference_model"
      2. Call `update_module` with action: "update_field", field_definition: { reference_model: "LandingPage" }
      3. Report: "✅ Fixed! Please reload the canvas."

      ## Example 3: Add a Dashboard Canvas
      
      User: "Add a dashboard to the Events module"
      
      Call `update_module` with:
         - module_slug: "events"
         - action: "add_canvas"
         - canvas_definition: { 
             name: "Events Dashboard", 
             canvas_type: "dashboard"
           }
      Report: "✅ Created dashboard canvas! Load it with: load_canvas('module_events_events_dashboard')"
    PROMPT
  },
  capabilities_definition: {
    description: 'Fixes, updates, and enhances existing modules AND their records',
    capabilities: ['fix_modules', 'update_fields', 'fix_canvases', 'fix_buttons', 'add_actions', 'update_records'],
    tool_allowlist: %w[update_module update_object get_data get_schema load_canvas ask_user diagnose_module get_platform_capabilities]
  }
)

# Create AgentTool entries for Module Architect
# Only add tools that exist in the catalog
catalog = Tools::ToolCatalog.instance
# update_object - for updating DATA RECORDS in custom modules
# update_module - for updating MODULE SCHEMA/DEFINITION (fields, canvases, etc.)
%w[update_module update_object get_data get_schema ask_user diagnose_module get_platform_capabilities create_object].each do |tool_name|
  if catalog.get_tool(tool_name).present? || tool_name == 'ask_user'
    AgentTool.find_or_create_by!(
      agent_plugin: module_architect,
      tool_name: tool_name
    )
  else
    puts "  ⚠️  Skipping tool '#{tool_name}' for Module Architect - not found in catalog"
  end
end

puts "✅ Module Architect Agent created with execution tools"
puts "🏭 Platform Factory seeding complete!"

