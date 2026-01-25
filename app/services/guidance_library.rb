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
    if canvas_context.present?
      canvas_type = canvas_context[:type] || canvas_context['type']
      
      case canvas_type
      when 'landing_page_editor', 'landing_page_viewer'
        return :landing_page_edit
      when 'workflow_designer'
        return :workflow_design
      when 'app_designer', 'design_studio'
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
      end
    end

    # Priority 2: Message content analysis (lightweight keyword detection)
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
      
      # Edit existing sections
      return :landing_page_edit if msg_lower.match?(/hero|cta|section|change the|update the|edit the/)
      
      return :workflow_design if msg_lower.match?(/workflow|automation|trigger|when.*then/)
      return :crm_operation if msg_lower.match?(/contact|lead|customer|crm|pipeline|opportunity/)
      return :email_creation if msg_lower.match?(/email|newsletter|campaign|subject\s*line/)
      return :integration_setup if msg_lower.match?(/connect|integration|sync|api|oauth/)
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
  def self.for_task(task_type, context: {})
    guidance = TASK_GUIDANCE[task_type.to_sym]
    return nil unless guidance

    # Build the guidance block
    build_guidance_block(task_type, guidance, context)
  end

  # Get relevant tools for a task type
  def self.tools_for_task(task_type)
    TASK_TOOLS[task_type.to_sym] || []
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
      title: "Integration Setup",
      expertise: <<~GUIDANCE.strip,
        You're helping set up integrations. Key principles:
        
        - Start by checking if the integration is already connected
        - OAuth integrations require browser redirect
        - Test the connection after setup
        - Understand what data will be synced
        - Set up appropriate permissions
        
        Troubleshooting:
        - If auth fails, check credentials/tokens
        - If sync fails, check data formats
        - Rate limits may apply to API calls
      GUIDANCE
      anti_hallucination: "Use integration tools to test connections. Report actual results, not assumptions."
    },

    app_design: {
      title: "App/Module & Landing Page Design",
      expertise: <<~GUIDANCE.strip,
        You're helping design landing pages, websites, or app modules.
        
        ## CRITICAL: Understand the Canvas State
        
        Look at the canvas_data to determine what you're working with:
        - If `plan_id` exists and `landing_page_id` is null → You're editing a DRAFT PLAN
        - If `landing_page_id` exists → You're editing a BUILT landing page
        
        ## When Editing a DRAFT PLAN (plan_id present, no landing_page_id):
        Use `plan_design` with `action: 'refine'` and pass:
        - `plan_id`: The ID from canvas_data
        - `refinements`: Object with the changes
          - `update_section`: { name: "cta", content: { headline: "New Text" } }
          - `add_section`: "testimonials"
          - `remove_section`: "pricing"
          - `update_colors`: { primary: "#hexcolor" }
        
        **DO NOT use landing page tools on a draft plan - use plan_design!**
        
        ## When Editing a BUILT Landing Page (landing_page_id present):
        Use `edit_landing_page_section` or `update_landing_page_content`
        
        ## Creating New Designs - Use "Plan → Build" workflow:
        1. Call `plan_design` with `action: 'create'` to create a visual plan
        2. Plan appears in design studio - user can review sections
        3. User can request refinements → use `action: 'refine'`
        4. When user says "build it" → use `action: 'build'`
        
        ## For APP MODULES:
        - Start with the data model (what entities, what fields?)
        - Consider relationships between entities
        - Plan CRUD operations needed
      GUIDANCE
      anti_hallucination: "Check canvas_data for plan_id vs landing_page_id. Use plan_design with action: 'refine' for draft plans. Only use landing page tools for BUILT pages."
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
      list_available_integrations
      get_integration_status
      test_integration
      configure_integration
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
    end

    parts.join("\n")
  end
end
