# frozen_string_literal: true

# GuidanceLibrary - Dynamic prompt fragments for task-specific expertise
#
# Instead of pre-defined "loadouts" or "agents", this provides small,
# focused guidance that gets injected into Amos based on detected task type.
#
# Philosophy:
# - Amos is always Amos (one identity)
# - Tools provide capabilities
# - Guidance provides expertise for specific task types
# - Everything is computed dynamically, not stored as entities
#
# Usage:
#   guidance = GuidanceLibrary.for_task(:landing_page_edit, context: { page_id: 123 })
#   # Returns focused guidance string to inject into system prompt
#
class GuidanceLibrary
  # ═══════════════════════════════════════════════════════════════
  # TASK TYPE DETECTION
  # ═══════════════════════════════════════════════════════════════

  # Detect task type from canvas context and message
  def self.detect_task_type(canvas_context: nil, message: nil)
    # Priority 1: Canvas context (user is looking at something specific)
    # Canvas context is AUTHORITATIVE - if user is on design_studio with a plan,
    # they're working on that plan, even if their message mentions "sections"
    if canvas_context.present?
      canvas_type = canvas_context[:type] || canvas_context['type']
      canvas_data = canvas_context[:data] || canvas_context['data'] || {}
      
      case canvas_type
      when 'landing_page_editor', 'landing_page_viewer'
        return :landing_page_edit
      when 'workflow_designer'
        return :workflow_design
      when 'app_designer', 'design_studio'
        # CRITICAL: If on design_studio with a plan_id, stay in app_design mode
        # This prevents switching to landing_page_edit when user says "change the section"
        return :app_design
      when 'integrations_manager'
        return :integration_setup
      when 'crm_dashboard', 'contacts', 'pipeline'
        return :crm_operation
      when 'email_template_editor'
        return :email_creation
      when 'analytics', 'operations_dashboard'
        return :analytics_review
      when 'document_viewer'
        return :document_analysis
      when 'custom_domains'
        return :custom_domain_management
      end
    end

    # Priority 2: Message content analysis (lightweight keyword detection)
    # ONLY used when there's no definitive canvas context
    if message.present?
      msg_lower = message.downcase
      
      # Distinguish between CREATE (new) and EDIT (existing) for landing pages
      if msg_lower.match?(/landing\s*page/)
        if msg_lower.match?(/create|make|build|generate|new/)
          return :landing_page_create
        else
          return :landing_page_edit
        end
      end
      
      # Website creation (always uses Plan → Build)
      return :website_create if msg_lower.match?(/website|multi.?page|site/)
      
      # Edit existing sections - BUT only if not on design_studio
      # (canvas check above already returned if on design_studio)
      return :landing_page_edit if msg_lower.match?(/hero|cta|section|change the|update the|edit the/)
      
      return :workflow_design if msg_lower.match?(/workflow|automation|trigger|when.*then/)
      
      # Integration detection - prioritize if integration keywords present with data keywords
      # E.g., "get stripe customers" should be integration, not CRM
      integration_keywords = msg_lower.match?(/connect|integration|sync|api|oauth|stripe|mailgun|hubspot|quickbooks|coinbase|from\s+(stripe|mailgun|hubspot)|via\s+(stripe|api)/)
      return :integration_setup if integration_keywords
      
      return :crm_operation if msg_lower.match?(/contact|lead|customer|crm|pipeline|opportunity/)
      return :email_creation if msg_lower.match?(/email|newsletter|campaign|subject\s*line/)
      return :custom_domain_management if msg_lower.match?(/custom\s*domain|cname|dns|godaddy|domain\s*verification|ses\s*email|send.*from.*domain/)
      return :app_design if msg_lower.match?(/app|module|database|schema|crud/)
      return :document_analysis if msg_lower.match?(/document|pdf|analyze|extract|summarize/)
      return :analytics_review if msg_lower.match?(/analytics|metrics|performance|dashboard|report/)
    end

    # Default: general assistance (no specific guidance needed)
    :general
  end

  # ═══════════════════════════════════════════════════════════════
  # GUIDANCE RETRIEVAL
  # ═══════════════════════════════════════════════════════════════

  # Get guidance for a specific task type
  # 
  # Parameters:
  #   task_type: Symbol - the detected task type (e.g., :landing_page_edit)
  #   context: Hash - context from canvas (landing_page_id, etc.)
  #   entity: Entity (optional) - for loading learned experiences
  #
  # Returns: String - formatted guidance block for prompt injection
  #
  def self.for_task(task_type, context: {}, entity: nil)
    guidance = TASK_GUIDANCE[task_type.to_sym]
    return nil unless guidance

    # Build the guidance block (static expertise)
    block = build_guidance_block(task_type, guidance, context)
    
    # Inject learned experiences from Training-Free GRPO (dynamic)
    if entity.present?
      experiences_block = inject_learned_experiences(task_type, entity)
      block = "#{block}\n\n#{experiences_block}" if experiences_block.present?
    end
    
    block
  end

  # Get relevant tools for a task type
  def self.tools_for_task(task_type)
    TASK_TOOLS[task_type.to_sym] || []
  end
  
  # ═══════════════════════════════════════════════════════════════
  # LEARNED EXPERIENCES (Training-Free GRPO integration)
  # ═══════════════════════════════════════════════════════════════
  
  # Inject learned experiences from TaskExperience model
  # These are distilled from comparing successful vs failed task executions
  def self.inject_learned_experiences(task_type, entity)
    return nil unless defined?(TaskExperience)
    
    TaskExperience.for_prompt(entity: entity, task_type: task_type.to_s, limit: 5)
  rescue => e
    Rails.logger.warn "[GuidanceLibrary] Failed to load experiences: #{e.message}"
    nil
  end

  # ═══════════════════════════════════════════════════════════════
  # GUIDANCE DEFINITIONS
  # Small, focused prompt fragments - NOT full system prompts
  # ═══════════════════════════════════════════════════════════════

  TASK_GUIDANCE = {
    landing_page_create: {
      title: "Landing Page Creation",
      expertise: <<~GUIDANCE.strip,
        ## Plan → Build Workflow (REQUIRED)
        
        ### CALL plan_design IMMEDIATELY!
        When user asks to create a landing page, call `plan_design` right away.
        The tool auto-pulls BusinessProfile (company name, industry, colors).
        Show the visual plan first - user can refine from there.
        
        Don't ask "what's the goal?" or "what sections?" - just show a plan!
        The plan is easy to modify - it's better to show something than ask questions.
        
        ### User Reviews the Plan
        After seeing the plan, user can request changes:
        - Use `plan_design(action: 'refine', plan_id: X, refinements: {...})`
        
        ### Build on Approval  
        When user approves ("build it", "looks good"):
        - Call `plan_design(action: 'build', plan_id: X)`
        
        ### Listing and Loading Existing Plans
        - "Show my plans" → `plan_design(action: 'list')`
        - "Open plan 5" → `plan_design(action: 'load', plan_id: 5)`
        - Plans also appear in Created Assets canvas
        
        ## CRITICAL
        ✅ Call plan_design IMMEDIATELY when user asks for a landing page
        ❌ Don't ask clarifying questions first - show the plan!
        ❌ Never call generate_ai_landing_page directly
      GUIDANCE
      anti_hallucination: "IMMEDIATELY call plan_design. Don't ask questions - show the plan first! User can refine after seeing it."
    },

    website_create: {
      title: "Website Creation",
      expertise: <<~GUIDANCE.strip,
        You're helping create a multi-page website. Use the Plan → Build workflow:
        
        1. FIRST: Call `plan_design` with design_type: 'website'
           - This creates a blueprint with multiple pages
           - Shows navigation structure, page sections, colors
        
        2. Let the user review and customize pages
           - Add pages: plan_design(action: 'add_page', page_name: 'About')
           - Remove pages: plan_design(action: 'remove_page', page_name: 'About')
           - Refine sections, colors, content
        
        3. When ready → Call `plan_design` with action: 'build'
           - Creates Website + WebsitePages
           - Opens website editor
        
        Key principles:
        - Start with 3-5 key pages (Home, About, Services/Products, Contact)
        - Pages share navigation and styling
        - Each page can have its own sections
      GUIDANCE
      anti_hallucination: "Use plan_design with design_type: 'website'. Always show the multi-page plan first."
    },

    landing_page_edit: {
      title: "Landing Page Editing",
      expertise: <<~GUIDANCE.strip,
        ## FIRST: Check what you're editing!
        
        Look at the canvas context:
        - If `plan_id` is set but NO `landing_page_id` → This is a DRAFT PLAN, use `plan_design` with action: 'refine'
        - If `landing_page_id` is set → This is a BUILT page, use landing page tools below
        
        ## For BUILT landing pages (has landing_page_id):
        
        - ALWAYS use `read_landing_page_sections` first to understand current structure
        - Use `edit_landing_page_section` for surgical edits - specify exact section IDs
        - Preserve existing content unless explicitly asked to change it
        - For layout changes (full-width, centering), the tool handles parent containers
        - For color changes, specify the exact color value
        - After edits, confirm what changed and offer to make additional adjustments
        
        ## For DRAFT plans (has plan_id but no landing_page_id):
        
        Use `plan_design` with:
        - action: 'refine'
        - plan_id: [the plan ID from context]
        - refinements: { update_section: { name: "cta", content: { ... } } }
        
        Common issues to avoid:
        - Don't use landing page tools on draft plans!
        - Don't recreate entire sections when making small changes
        - Don't remove content that wasn't asked to be removed
      GUIDANCE
      anti_hallucination: "CHECK the canvas data for plan_id vs landing_page_id. Draft plans need plan_design with action:'refine'. Only built pages use edit_landing_page_section."
    },

    workflow_design: {
      title: "Workflow Design",
      expertise: <<~GUIDANCE.strip,
        You're helping design an automation workflow. Key principles:
        
        - Workflows have: Triggers → Actions → Outputs
        - Use the workflow designer canvas to visualize
        - Every workflow needs a clear trigger (webhook, schedule, event, manual)
        - Actions should be deterministic and testable
        - Consider error handling and edge cases
        - Build incrementally - start simple, add complexity
        
        Workflow types:
        - Form submission → notification/CRM update
        - Scheduled tasks → reports, reminders
        - Integration sync → data flow between systems
        - Event-driven → respond to system events
      GUIDANCE
      anti_hallucination: "Use workflow tools to create/modify workflows. Don't describe what you would do - actually do it."
    },

    crm_operation: {
      title: "CRM Operations",
      expertise: <<~GUIDANCE.strip,
        You're helping with CRM and contact management. Key principles:
        
        - Always verify contact data before making changes
        - Use search to find contacts before creating duplicates
        - Pipeline stages should flow logically
        - Keep notes and activity logs for context
        - Respect data privacy - don't expose sensitive info unnecessarily
        
        Best practices:
        - Segment contacts by meaningful criteria
        - Track interactions and follow-ups
        - Use tags consistently
        - Keep contact records clean and updated
      GUIDANCE
      anti_hallucination: "Use CRM tools to search, create, or update contacts. Confirm changes after making them."
    },

    email_creation: {
      title: "Email Creation",
      expertise: <<~GUIDANCE.strip,
        You're helping create email content. Key principles:
        
        - Subject lines: Clear, compelling, not spammy
        - Keep emails focused on one main message
        - Include clear call-to-action
        - Consider mobile readability
        - Personalization when possible
        - Test before sending
        
        Structure:
        - Hook in first line
        - Value proposition
        - Clear CTA
        - Professional signature
      GUIDANCE
      anti_hallucination: "Use email tools to create and preview. Don't just describe the email - create it."
    },

    integration_setup: {
      title: "Integration Setup & Data",
      expertise: <<~GUIDANCE.strip,
        You're helping with integrations - both setup and data operations.
        
        ## CONNECTION SETUP
        - Check if integration is already connected with `list_connections`
        - OAuth integrations require browser redirect
        - Test the connection after setup
        
        ## EXECUTING INTEGRATION ACTIONS
        ALWAYS use this workflow when calling integration APIs:
        
        1. **First: List available actions**
           ```
           list_integration_actions(integration: "stripe")
           ```
           This shows you EXACTLY what actions exist and what inputs they need.
        
        2. **Then: Execute with correct parameters**
           ```
           execute_integration_action(
             integration: "stripe",
             action: "list_customers",
             inputs: { limit: 10 }
           )
           ```
        
        ## IMPORTANT PARAMETER NAMES
        - Use `action` not `operation`
        - Use `inputs` not `params`
        - Check `list_integration_actions` output for required fields!
        
        ## COMMON ACTIONS (always verify with list_integration_actions first!)
        - Stripe: create_customer, list_customers, get_customer
        - Mailgun: send_email, list_messages
        - HubSpot: create_contact, list_contacts, create_deal
        
        ## LEARNING BEFORE ACTING
        If you're unsure about API-specific quirks (like QuickBooks query syntax):
        ```
        query_integration_knowledge(
          question: "How do I filter open invoices in QuickBooks?",
          integration_name: "quickbooks"
        )
        ```
        This queries the integration knowledge base with API docs and best practices.
        
        ## Building Integration Knowledge
        Use `create_rag_store` to build knowledge bases from API documentation for
        integrations that don't have pre-built knowledge.
        
        ## Troubleshooting
        - If auth fails, check credentials/tokens
        - If action not found, call list_integration_actions first
        - If unsure about API syntax, use query_integration_knowledge
        - Rate limits may apply to API calls
      GUIDANCE
      anti_hallucination: "ALWAYS call list_integration_actions FIRST to see available actions and their exact input requirements. Use query_integration_knowledge for API-specific questions. Do NOT guess parameter names."
    },

    app_design: {
      title: "App/Module & Landing Page Design",
      expertise: <<~GUIDANCE.strip,
        You're helping design landing pages, websites, or app modules.
        
        ## CRITICAL: YOU ARE EDITING A DRAFT PLAN
        
        The user is on the Design Studio canvas with a plan. When they ask to 
        change sections, backgrounds, colors, text - they want to modify the PLAN,
        not a built landing page!
        
        **ALWAYS use `plan_design` with `action: 'refine'` for ANY changes.**
        
        ## Common Refinement Examples:
        
        "Make the features section lighter" →
        ```json
        { "action": "refine", "plan_id": 7, "refinements": { 
          "update_section": { "name": "features", "background": "light" }
        }}
        ```
        
        "Change the hero headline" →
        ```json
        { "action": "refine", "plan_id": 7, "refinements": { 
          "update_section": { "name": "hero", "content": { "headline": "New Headline" }}
        }}
        ```
        
        "Add a pricing section" →
        ```json
        { "action": "refine", "plan_id": 7, "refinements": { 
          "add_section": "pricing"
        }}
        ```
        
        "Change the primary color" →
        ```json
        { "action": "refine", "plan_id": 7, "refinements": { 
          "update_colors": { "primary": "#1a2b3c" }
        }}
        ```
        
        ## NEVER DO THESE:
        ❌ Use `edit_landing_page_section` - that's for BUILT pages only
        ❌ Use `read_landing_page_sections` - the plan IS the sections
        ❌ Try to find a landing_page_id - the plan hasn't been built yet!
        
        ## When User Says "Build It":
        Call `plan_design` with `action: 'build'` and the plan_id
        
        ## For APP MODULES:
        - Start with the data model (what entities, what fields?)
        - Consider relationships between entities
        - Plan CRUD operations needed
      GUIDANCE
      anti_hallucination: "You're editing a DRAFT PLAN. Use plan_design(action: 'refine') for ALL changes. NEVER use landing page tools - the plan isn't built yet!"
    },

    document_analysis: {
      title: "Document Analysis",
      expertise: <<~GUIDANCE.strip,
        You're helping analyze documents. Key principles:
        
        - Wait for document processing to complete
        - Summarize key points first
        - Extract specific data when asked
        - Reference page numbers/sections
        - Maintain accuracy - quote when needed
        
        Capabilities:
        - Text extraction
        - Summarization
        - Key information extraction
        - Question answering about content
      GUIDANCE
      anti_hallucination: "Base analysis on actual document content. Don't fabricate or assume content."
    },

    analytics_review: {
      title: "Analytics Review",
      expertise: <<~GUIDANCE.strip,
        You're helping review analytics and metrics. Key principles:
        
        - Present data clearly and accurately
        - Highlight trends and anomalies
        - Provide actionable insights
        - Compare to relevant benchmarks
        - Suggest improvements based on data
        
        Key metrics to consider:
        - Engagement rates
        - Conversion funnels
        - Growth trends
        - Performance benchmarks
      GUIDANCE
      anti_hallucination: "Use actual data from analytics tools. Don't invent statistics."
    },

    custom_domain_management: {
      title: "Custom Domain Management",
      expertise: <<~GUIDANCE.strip,
        You're helping configure custom domains for landing pages, websites, and email.
        
        ## Use `manage_custom_domain` tool with these actions:
        
        ### Setting up a new custom domain
        1. Call `manage_custom_domain(action: 'create', domain_name: 'example.com')`
        2. This returns DNS records (CNAME and TXT) the user must add
        3. Show the user clearly what records to add and where
        
        ### Verifying DNS is configured
        - Call `manage_custom_domain(action: 'verify', domain_name: 'example.com')`
        - Reports if CNAME and TXT records are properly configured
        
        ### Auto-configuring DNS via GoDaddy
        - If user has GoDaddy connected, offer to auto-configure
        - Call `manage_custom_domain(action: 'auto_configure_dns', custom_domain_id: X, integration_connection_id: Y)`
        
        ### Setting up email sending (SES)
        - Call `manage_custom_domain(action: 'setup_ses', domain_name: 'example.com')`
        - Returns TXT and DKIM CNAME records for email verification
        - Call `manage_custom_domain(action: 'verify_ses', domain_name: 'example.com')` to check
        
        ### Listing all domains
        - Call `manage_custom_domain(action: 'list')` to see all configured domains
        
        ## Key Points
        - DNS changes can take up to 48 hours to propagate
        - Always explain the records clearly to the user
        - Offer to load the custom_domains canvas to show all domains
      GUIDANCE
      anti_hallucination: "Use manage_custom_domain tool. Report actual verification results, not assumptions about DNS configuration."
    },

    general: {
      title: "General Assistance",
      expertise: nil,  # No special guidance needed
      anti_hallucination: nil
    }
  }.freeze

  # ═══════════════════════════════════════════════════════════════
  # TASK-SPECIFIC TOOL SETS
  # What tools should be prioritized for each task type
  # ═══════════════════════════════════════════════════════════════

  TASK_TOOLS = {
    landing_page_create: %w[
      plan_design
      generate_ai_landing_page
    ],

    website_create: %w[
      plan_design
    ],

    landing_page_edit: %w[
      plan_design
      read_landing_page_sections
      edit_landing_page_section
      update_landing_page_content
      get_landing_page_details
      list_landing_pages
    ],

    workflow_design: %w[
      create_workflow
      get_workflow
      list_workflows
      add_workflow_step
      save_workflow
      compile_workflow
    ],

    crm_operation: %w[
      search_contacts
      create_contact
      update_contact
      get_contact_details
      list_pipeline_stages
      update_opportunity
    ],

    email_creation: %w[
      create_email_template
      preview_email
      send_email
      list_email_templates
    ],

    integration_setup: %w[
      list_connections
      list_integration_actions
      execute_integration_action
      query_integration_knowledge
      list_available_integrations
      get_integration_status
      test_integration
      configure_integration
      create_rag_store
    ],

    app_design: %w[
      plan_design
      generate_ai_landing_page
      create_app_module
      create_tool
      list_app_modules
      list_landing_pages
    ],

    document_analysis: %w[
      analyze_document
      extract_document_data
      summarize_document
    ],

    analytics_review: %w[
      get_analytics_summary
      get_entity_metrics
      get_usage_stats
    ],

    custom_domain_management: %w[
      manage_custom_domain
      list_available_integrations
      get_integration_status
    ],

    general: []  # No specific tools - use standard set
  }.freeze

  private

  def self.build_guidance_block(task_type, guidance, context)
    return nil if guidance[:expertise].blank?

    block = <<~BLOCK
      ## 🎯 CURRENT FOCUS: #{guidance[:title]}
      
      #{guidance[:expertise]}
    BLOCK

    # Add context-specific info
    if context.present?
      context_info = format_context(task_type, context)
      block += "\n\n## 📍 CONTEXT\n#{context_info}" if context_info.present?
    end

    # Add anti-hallucination reminder if present
    if guidance[:anti_hallucination].present?
      block += "\n\n⚠️ IMPORTANT: #{guidance[:anti_hallucination]}"
    end

    block
  end

  def self.format_context(task_type, context)
    parts = []

    case task_type
    when :landing_page_edit
      if context[:landing_page_id] || context['landing_page_id']
        lp_id = context[:landing_page_id] || context['landing_page_id']
        parts << "- Landing Page ID: #{lp_id}"
        
        lp = LandingPage.find_by(id: lp_id)
        if lp
          parts << "- Title: #{lp.title}"
          parts << "- Status: #{lp.status}"
        end
      end

    when :workflow_design
      if context[:workflow_id] || context['workflow_id']
        parts << "- Workflow ID: #{context[:workflow_id] || context['workflow_id']}"
      end

    when :crm_operation
      if context[:contact_id] || context['contact_id']
        parts << "- Contact ID: #{context[:contact_id] || context['contact_id']}"
      end

    when :custom_domain_management
      if context[:custom_domain_id] || context['custom_domain_id']
        parts << "- Custom Domain ID: #{context[:custom_domain_id] || context['custom_domain_id']}"
      end
      if context[:domain_name] || context['domain_name']
        parts << "- Domain: #{context[:domain_name] || context['domain_name']}"
      end
    end

    parts.join("\n")
  end
end
