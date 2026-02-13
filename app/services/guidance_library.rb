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
      # Only match explicit "landing page" requests — NOT general "page" which could be a website page
      if msg_lower.match?(/landing\s*page|marketing\s*page|promo\s*page|signup\s*page/)
        if msg_lower.match?(/create|make|build|generate|new/)
          return :landing_page_create
        else
          return :landing_page_edit
        end
      end
      
      # Web App creation — external-facing functional apps (must check BEFORE website and app)
      # Matches: "build me an app that customers can use", "task tracker app", "customer portal"
      if msg_lower.match?(/portal|external\s*app|public\s*app|customer.*(app|tool|dashboard)|(app|tool).*(customer|user|public|external)/) ||
         (msg_lower.match?(/tracker|planner|board|manager/) && msg_lower.match?(/app|build|create|make/)) ||
         msg_lower.match?(/web\s*app/)
        return :web_app_create
      end
      
      # Website creation (multi-page sites)
      return :website_create if msg_lower.match?(/website|multi.?page|company\s*site|portfolio\s*site/)
      
      # Edit existing sections - BUT only if not on design_studio
      # (canvas check above already returned if on design_studio)
      return :landing_page_edit if msg_lower.match?(/hero|cta|section|change the|update the|edit the/)
      
      # Email sequence detection - must check BEFORE workflow/automation
      if msg_lower.match?(/email\s*(sequence|series|drip|nurture|onboarding\s*flow)|welcome\s*(sequence|series)|follow.?up\s*series|day\s*\d+.*day\s*\d+|(drip|nurture)\s*(campaign|flow|sequence)|emails?\s*over\s*time/)
        return :email_sequence_create
      end
      
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
  # Cached for 5 minutes per entity+task_type to avoid 4 DB queries per request
  def self.inject_learned_experiences(task_type, entity)
    return nil unless defined?(TaskExperience)
    
    cache_key = "guidance:experiences:#{entity.id}:#{task_type}"
    Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      TaskExperience.for_prompt(entity: entity, task_type: task_type.to_s, limit: 5)
    end
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
        ## When to Use Landing Page
        USE FOR: Single marketing/conversion page — product launches, lead capture, event registration, newsletter signup, promotions.
        These are standalone marketing pages with hero sections, CTAs, testimonials, and signup forms.
        DO NOT use landing_page for functional apps, dashboards, trackers, or tools (use web_app instead).
        
        ## Create
        `platform_create(type: "landing_page", data: { title: "...", description: "..." })`
        After creation → load_canvas(canvas_name: "landing_page_editor", canvas_data: { landing_page_id: ID })
        
        ## Context
        - BusinessProfile contains company name, colors, industry
        - Pages can be saved as drafts before publishing
        - IMAGE + LANDING PAGE: 1) platform_execute(action: "generate_image") → get URL, 2) platform_update landing page section
      GUIDANCE
      anti_hallucination: nil
    },

    website_create: {
      title: "Website Creation",
      expertise: <<~GUIDANCE.strip,
        ## When to Use Website
        USE FOR: Multi-page sites with shared layout — company sites, portfolios, documentation, content sites.
        NOT for single marketing pages (use landing_page) or functional apps (use web_app).
        
        ## Create
        `platform_create(type: "website", data: { name: "...", pages: [{title: "...", description: "..."}] })`
        Each page auto-detects purpose from description, or set page_purpose: "functional" or "marketing".
        After creation → load_canvas(canvas_name: "my_creations", canvas_data: { type: "website" })
        
        ## Editing Individual Pages
        To edit a specific website page inline:
        load_canvas(canvas_name: "website_page_editor", canvas_data: { website_page_id: PAGE_ID })
        or: load_canvas(canvas_name: "website_page_editor", canvas_data: { website_id: SITE_ID, page_slug: "about" })
        
        ## Context
        - Shared navigation across pages
        - Common pages: Home, About, Services, Contact
        - Functional pages get app-like UI (tables, forms, dashboards)
        - Marketing pages get conversion-focused layouts (hero, testimonials, CTAs)
      GUIDANCE
      anti_hallucination: nil
    },

    web_app_create: {
      title: "Web App Creation",
      expertise: <<~GUIDANCE.strip,
        ## When to Use Web App
        USE FOR: External-facing functional applications — task trackers, CRM portals, customer dashboards, form-based tools, any app with data + UI + optional auth.
        If user says "build me an app that customers/users can access" → web_app.
        NOT for marketing pages (landing_page) or content sites (website).
        
        ## Create
        `platform_create(type: "web_app", data: { name: "...", pages: [...], modules: ["module_slug"], auth: {methods: ["email"]} })`
        Creates Website with FUNCTIONAL pages + WebApp record linking modules + auth.
        
        ## Flow
        1. Build internal module if needed: platform_create(type: "app", data: {...})
        2. Create the web app: platform_create(type: "web_app", data: { name: "...", pages: [...], modules: ["slug"] })
        3. Gets subdomain (e.g., name.app.amoslabs.com)
        4. After creation → load_canvas(canvas_name: "my_creations", canvas_data: { type: "web_app" })
        
        ## Decision Shortcuts
        - "build a task tracker app" → web_app (tracker + app = functional external tool)
        - "create a customer portal" → web_app
        - "build a dashboard for my team" → web_app
      GUIDANCE
      anti_hallucination: nil
    },

    landing_page_edit: {
      title: "Landing Page Editing",
      expertise: <<~GUIDANCE.strip,
        ## Context Check
        
        Look at canvas_data to understand what's being edited:
        - `landing_page_id` present → This is a built page
        - `plan_id` only → This is a draft design
        
        ## Available Tools
        - `read_landing_page_sections` — Get current structure of built pages
        - `edit_landing_page_section` — Modify specific sections
        - `load_canvas(canvas_name: "landing_page_editor", canvas_data: { landing_page_id: X })` — Open visual editor
      GUIDANCE
      anti_hallucination: nil
    },

    workflow_design: {
      title: "Workflow Design",
      expertise: <<~GUIDANCE.strip,
        ## Available Approaches
        
        **Visual Builder:**
        `load_canvas(canvas_name: "workflow_designer")` — Drag-drop workflow builder
        
        **Programmatic:**
        `platform_create(type: "workflow", data: { name: "...", trigger_type: "..." })`
        
        **Templates:**
        `platform_query(type: "automation_recipes")` — Pre-built workflow templates
        
        ## Workflow Components
        - **Triggers**: form_submission, schedule, event, webhook, manual
        - **Actions**: send_email, update_record, call_integration, delay, etc.
        - **Conditions**: Branch logic based on data values
        
        ## Monitor
        `load_canvas(canvas_name: "automation_dashboard")` — View all automations
      GUIDANCE
      anti_hallucination: nil
    },

    crm_operation: {
      title: "CRM Operations",
      expertise: <<~GUIDANCE.strip,
        ## Available Tools
        - `platform_query(type: "contacts", ...)` — Search and list contacts
        - `platform_create(type: "contact", data: {...})` — Create contacts
        - `platform_update(type: "contact", id: X, data: {...})` — Update contacts
        - `load_canvas(canvas_name: "pipeline_viewer")` — Visual sales pipeline
        
        ## Key Models
        - Contact: email, first_name, last_name, status, lifecycle_stage, tags
        - Opportunity: linked to contacts, has stages and value
        - Activity: interaction history on contacts
        - ContactGroup: for segmentation
      GUIDANCE
      anti_hallucination: nil
    },

    email_creation: {
      title: "Email Creation",
      expertise: <<~GUIDANCE.strip,
        ## Available Tools
        - `platform_create(type: "email_template", data: {...})` — Create template
        - `platform_query(type: "email_templates")` — List templates
        - `load_canvas(canvas_name: "sequence_manager")` — Email sequence builder
        
        ## Key Fields
        - name, subject, body (HTML), preheader
        - Personalization: {{contact.first_name}}, {{contact.email}}, etc.
      GUIDANCE
      anti_hallucination: nil
    },

    email_sequence_create: {
      title: "Email Sequence / Drip Campaign Creation",
      expertise: <<~GUIDANCE.strip,
        ## Email Sequence vs Automation vs Campaign
        - **Email Sequence**: Multi-step drip flow with delays (welcome series, nurture, onboarding). Use `platform_create(type: "email_sequence")`.
        - **Automation**: Single triggered email (e.g., "send welcome email on signup"). Use `platform_create(type: "automation")`.
        - **Campaign**: One-time blast to a list. Use `platform_create(type: "campaign")`.
        
        ## Creating an Email Sequence (Multi-Step Flow)
        1. Create email templates for each step: `platform_create(type: "email_template", data: { name: "Welcome Day 1", subject: "...", body: "..." })`
        2. Create the sequence with steps and delays:
           ```
           platform_create(type: "email_sequence", data: {
             name: "Welcome Series",
             steps: [
               { delay_days: 0, email_template_id: TEMPLATE_1_ID, subject: "Welcome!" },
               { delay_days: 3, email_template_id: TEMPLATE_2_ID, subject: "Getting Started" },
               { delay_days: 7, email_template_id: TEMPLATE_3_ID, subject: "Pro Tips" }
             ]
           })
           ```
        3. Show results: `load_canvas(canvas_name: "my_creations", data: { type: "automation" })`
        
        ## CRITICAL
        - If user mentions "Day 1, Day 3, Day 7" or similar multi-step timing → ALWAYS use email_sequence, NOT standalone automations.
        - Create templates FIRST, then reference their IDs in sequence steps.
      GUIDANCE
      anti_hallucination: nil
    },

    integration_setup: {
      title: "Integration Setup & Data",
      expertise: <<~GUIDANCE.strip,
        ## Available Tools
        - `platform_query(type: "connections")` — See connected integrations
        - `platform_query(type: "integrations")` — See available integrations
        - `platform_query(type: "integration_actions", integration: "stripe")` — Discover operations
        - `platform_execute(action: "integration", integration: "stripe", operation: "list_customers")` — Call integration APIs
        - `load_canvas(canvas_name: "integrations_manager")` — Visual integration manager
        
        ## Using Existing Integrations
        Smart cascade: tries IntegrationAction first, falls back to raw operation.
        ```
        platform_execute(action: "integration", integration: "stripe", operation: "list_customers", params: { limit: 10 })
        ```
        
        ## Setting Up NEW Integrations — Exact Flow
        1. Research the API: Use web_search to find docs, base URL, auth type (api_key, bearer_token, oauth2, basic_auth), and endpoints.
        2. Ask user for requirements (but NEVER ask for credentials).
        3. Build the shell: platform_create(type: "integration", data: { name: "...", base_url: "...", auth_type: "api_key", category: "crm", operations: [...] })
        4. System opens Integrations canvas where user enters credentials securely — NOT through chat.
        5. After connected, test with platform_execute.
        
        ## SECURITY
        NEVER ask for API keys, tokens, passwords, or credentials in chat.
        Credentials are entered ONLY through the Integrations canvas UI.
        If a user pastes credentials in chat, tell them to delete the message and use the Integrations panel.
      GUIDANCE
      anti_hallucination: nil
    },

    app_design: {
      title: "App/Module Design",
      expertise: <<~GUIDANCE.strip,
        ## Building New Apps/Modules
        
        **Internal app** (data module, AMOS-only):
          platform_create(type: "app", data: { name: "App Name", description: "What it does and key features" })
          Build takes 30-60s. Creates: database tables, list/form/detail canvases, CRUD tools, agent plugins.
          After build → load_canvas(canvas_name: "module_manager", canvas_data: { app_module_id: ID })
          NEVER say "I've created your module" unless platform_create returned success with module IDs.
        
        **External-facing app** (public, with auth):
          platform_create(type: "web_app", data: { name: "...", pages: [...], modules: ["slug"], auth: {methods: ["email"]} })
          Creates Website + WebApp record + links modules + manages auth.
        
        ## Using Existing Modules
        CRUD records: platform_create(type: "task", data: {...}), platform_query(type: "tasks")
        Discover types: platform_query(type: "schema")
        Module slugs: e.g., "project_management_task". Sub-modules filter by parent ID.
        Update module: platform_update(type: "app_module", id: ID, data: {...}). Do NOT create new when user wants to modify.
        
        ## Schema Field Types
        text, textarea, number, currency, date, datetime, select, multi_select, boolean, reference, file, json
        
        ## Context
        If on design_studio with a plan_id, the user is working on a design draft.
      GUIDANCE
      anti_hallucination: nil
    },

    document_analysis: {
      title: "Document Analysis",
      expertise: <<~GUIDANCE.strip,
        ## Available Tools
        - `read_file(path: "...")` — Read uploaded documents
        - `platform_query(type: "documents")` — List uploaded files
        - `load_canvas(canvas_name: "document_viewer", canvas_data: { document_id: X })` — Visual document viewer
        
        ## Capabilities
        Text extraction, summarization, data extraction, Q&A on content.
      GUIDANCE
      anti_hallucination: nil
    },

    analytics_review: {
      title: "Analytics Review",
      expertise: <<~GUIDANCE.strip,
        ## Available Tools
        - `platform_query(type: "analytics", ...)` — Query metrics
        - `load_canvas(canvas_name: "analytics_dashboard")` — Visual analytics
        
        ## Key Metrics
        Engagement rates, conversion funnels, growth trends, performance benchmarks.
      GUIDANCE
      anti_hallucination: nil
    },

    custom_domain_management: {
      title: "Custom Domain Management",
      expertise: <<~GUIDANCE.strip,
        ## Domain Setup Tool (platform handles all DNS automatically)
        Use `manage_custom_domain` for DNS setup flows. The platform orchestrates everything.

        1. **Web Publishing**: `manage_custom_domain(action: "setup_web", domain_name: "example.com")`
           - Creates domain, generates CNAME target
           - If GoDaddy is connected: auto-pushes CNAME record + schedules verification
           - If no GoDaddy: returns manual DNS instructions for the user
        2. **Email Sending**: `manage_custom_domain(action: "setup_email", domain_id: ID)`
           - Creates SES identity, generates DKIM/SPF/DMARC/MX records
           - If GoDaddy connected: auto-pushes all email DNS records
        3. **Check Status**: `manage_custom_domain(action: "check_status", domain_id: ID)`
        4. **List Domains**: `manage_custom_domain(action: "list")`

        ## GoDaddy as Regular Integration
        GoDaddy is a standard integration. For general operations (list domains, check DNS records,
        manage records directly), use `execute_integration_action(integration: "godaddy", ...)`.
        The `manage_custom_domain` tool is only for the automated setup flows.

        ## Key Points
        - DNS setup is fully automated when GoDaddy is connected -- users don't need to understand records
        - DNS changes can take up to 48 hours to propagate (usually 15 min)
        - Always check status with `manage_custom_domain(action: "check_status")` before assuming ready
        - SSL is auto-provisioned after web DNS verification succeeds

        ## Visual Manager
        `load_canvas(canvas_name: "custom_domains")`
      GUIDANCE
      anti_hallucination: nil
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
      platform_create
      load_canvas
    ],

    website_create: %w[
      platform_create
      load_canvas
    ],

    web_app_create: %w[
      platform_create
      platform_query
      load_canvas
    ],

    landing_page_edit: %w[
      platform_query
      platform_update
      load_canvas
    ],

    workflow_design: %w[
      platform_create
      platform_query
    ],

    crm_operation: %w[
      platform_query
      platform_create
      platform_update
      load_canvas
    ],

    email_creation: %w[
      platform_create
      platform_query
      platform_execute
    ],

    email_sequence_create: %w[
      platform_create
      platform_query
      load_canvas
    ],

    integration_setup: %w[
      platform_query
      platform_execute
      discover
      load_canvas
    ],

    app_design: %w[
      platform_create
      platform_query
      load_canvas
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
      execute_integration_action
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
