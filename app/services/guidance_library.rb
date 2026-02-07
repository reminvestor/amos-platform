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
        ## Available Approaches
        
        **Visual Builder (recommended for most users):**
        `load_canvas(canvas_name: "design_studio")` — Opens the drag-drop landing page builder
        
        **Query existing pages:**
        `platform_query(type: "landing_pages")` — See what already exists
        
        **View created assets:**
        `load_canvas(canvas_name: "my_creations")` — Show all user's creations
        
        ## Context
        - BusinessProfile contains company name, colors, industry
        - The design studio provides AI-assisted content generation
        - Pages can be saved as drafts before publishing
      GUIDANCE
      anti_hallucination: nil
    },

    website_create: {
      title: "Website Creation",
      expertise: <<~GUIDANCE.strip,
        ## Available Approaches
        
        **Visual Builder:**
        `load_canvas(canvas_name: "design_studio")` — Multi-page website builder
        
        ## Context
        - Websites have multiple pages with shared navigation
        - Common pages: Home, About, Services, Contact
        - Each page can have independent sections
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

    integration_setup: {
      title: "Integration Setup & Data",
      expertise: <<~GUIDANCE.strip,
        ## Available Tools
        - `platform_query(type: "connections")` — See connected integrations
        - `platform_query(type: "integrations")` — See available integrations
        - `platform_execute(operation: "integration_action", ...)` — Call integration APIs
        - `load_canvas(canvas_name: "integrations_manager")` — Visual integration manager
        - `discover(query: "stripe actions")` — Find available integration actions
        
        ## Parameter Pattern
        ```
        platform_execute(
          operation: "integration_action",
          params: { 
            integration: "stripe", 
            action: "list_customers", 
            inputs: { limit: 10 } 
          }
        )
        ```
        
        ## Knowledge Base
        Use `discover` to find API-specific documentation and quirks for integrations.
      GUIDANCE
      anti_hallucination: nil
    },

    app_design: {
      title: "App/Module Design",
      expertise: <<~GUIDANCE.strip,
        ## Available Approaches
        
        **Visual Builder:**
        `load_canvas(canvas_name: "app_designer")` — Drag-drop app builder
        
        **Programmatic:**
        ```
        platform_create(type: "app_module", data: {
          name: "Project Tracker",
          schema: { fields: [...] }
        })
        ```
        
        ## Schema Field Types
        text, textarea, number, currency, date, datetime, select, 
        multi_select, boolean, reference, file, json
        
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
        ## Available Tools
        - `platform_execute(operation: "manage_domain", params: { action: "create", domain: "..." })`
        - `platform_execute(operation: "manage_domain", params: { action: "verify", domain: "..." })`
        - `load_canvas(canvas_name: "custom_domains")` — Visual domain manager
        
        ## Actions
        - create: Returns DNS records (CNAME, TXT) to configure
        - verify: Checks if DNS is properly configured
        - setup_ses: Configure email sending from domain
        
        ## Note
        DNS changes can take up to 48 hours to propagate.
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
