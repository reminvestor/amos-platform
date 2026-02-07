# frozen_string_literal: true

module V3
  # SystemPromptBuilder - Builds the system prompt for V3 agent loop
  #
  # Key differences from V2:
  # - No modular prompt sections based on preprocessor classification
  # - Always includes: identity, user context, active skills, platform state
  # - No fast path / full path distinction
  # - Skills are loaded based on canvas context + message (DynamicContextService)
  # - Simpler, more consistent — the model gets the same quality prompt every time
  #
  class SystemPromptBuilder
    attr_reader :user, :entity, :session_id

    def initialize(user:, entity:, session_id: nil)
      @user = user
      @entity = entity
      @session_id = session_id
    end

    # Build the complete system prompt
    # @param current_canvas [String] Current canvas the user is viewing
    # @param message [String] The user's current message (for skill discovery)
    # @param intent_mode [Symbol] :personal, :ideate, :operate, :create
    def build(current_canvas: nil, message: nil, intent_mode: nil)
      parts = []

      # 1. Core identity (who is AMOS)
      parts << build_identity(intent_mode)

      # 2. User context (who are we talking to)
      parts << build_user_context

      # 3. Current datetime and location
      parts << build_datetime_context

      # 4. Active skills (loaded based on context)
      parts << build_skills_context(current_canvas, message)

      # 5. Platform state summary
      parts << build_platform_summary

      # 6. Canvas context (what the user is looking at)
      parts << build_canvas_context(current_canvas) if current_canvas.present?

      # 7. V3 tool usage instructions
      parts << build_tool_instructions

      # 8. Learned behaviors and memories
      parts << build_learned_context

      parts.compact.reject(&:blank?).join("\n\n")
    end

    private

    def build_identity(intent_mode)
      # Use AmosIdentity for core identity (reuse what we have)
      space_definition = user&.active_space_definition rescue nil
      AmosIdentity.build_system_prompt(
        user: user,
        mode: intent_mode,
        space_definition: space_definition
      )
    end

    def build_user_context
      user_name = user&.full_name || user&.first_name || "User"
      entity_name = entity&.name || "Organization"

      <<~CONTEXT
        ## Current User
        - Name: #{user_name}
        - Organization: #{entity_name}
        - Role: #{user&.role || 'member'}
      CONTEXT
    end

    def build_datetime_context
      # User doesn't have timezone column - use entity settings or default
      tz = entity&.settings&.dig("timezone") || "America/Los_Angeles"
      current_time = Time.current.in_time_zone(tz)
      "📅 #{current_time.strftime('%A, %B %d, %Y at %I:%M %p %Z')}"
    end

    def build_skills_context(current_canvas, message)
      return nil if message.blank? && current_canvas.blank?

      # Use DynamicContextService (already exists!) for skill discovery
      begin
        ctx_service = DynamicContextService.new(user: user, entity: entity)
        canvas_ctx = current_canvas.present? ? { type: current_canvas } : nil
        
        result = ctx_service.build_context(
          canvas_context: canvas_ctx,
          message: message
        )

        guidance = result[:guidance_block]
        return nil if guidance.blank?

        <<~SKILLS
          ## Active Skills & Guidance
          #{guidance}
        SKILLS
      rescue => e
        Rails.logger.warn "[V3::SystemPrompt] Skills loading error: #{e.message}"
        nil
      end
    end

    def build_platform_summary
      # Quick stats about the platform (lightweight)
      stats = {}
      begin
        stats[:contacts] = entity.contacts.count
        stats[:campaigns] = entity.campaigns.count
        stats[:landing_pages] = entity.landing_pages.count
        stats[:active_integrations] = entity.connections.where(status: "active").count rescue 0
      rescue => e
        Rails.logger.debug "[V3::SystemPrompt] Stats error: #{e.message}"
      end

      return nil if stats.empty?

      items = stats.map { |k, v| "#{k.to_s.titleize}: #{v}" }.join(" | ")
      "## Platform: #{entity&.name}\n#{items}"
    end

    def build_canvas_context(current_canvas)
      # Map canvas type to clear context
      context = case current_canvas
                when "landing_page_editor"
                  "The user is viewing a landing page in the editor. They may ask you to edit sections, content, and styling.\n" \
                  "To edit a SECTION by name (hero, features, pricing, etc.):\n" \
                  "  platform_update(type: 'landing_page', id: ID, data: { section: 'hero', instruction: 'Remove the image and center the text' })\n" \
                  "To read the page sections:\n" \
                  "  platform_update(type: 'landing_page', id: ID, data: { read_sections: true })\n" \
                  "To replace full HTML:\n" \
                  "  platform_update(type: 'landing_page', id: ID, data: { html_content: '...' })\n" \
                  "The landing page ID should be in the canvas context below."
                when "campaign_viewer"
                  "The user is viewing a campaign. Help them manage recipients, content, and sending."
                when "integrations_manager"
                  "The user is managing integrations. Help them connect, configure, and use external services."
                when "pipeline_viewer", "contact_detail"
                  "The user is in CRM mode. Help them manage contacts, opportunities, and activities."
                when "analytics_dashboard"
                  "The user is viewing analytics. Help them understand metrics and create visualizations."
                when "support_tickets"
                  "The user is managing support tickets."
                else
                  "Current view: #{current_canvas.humanize}"
                end

      "## Current Context\n#{context}"
    end

    def build_tool_instructions
      <<~TOOLS
        ## Tools Available
        
        **Data:** `platform_query`, `platform_create`, `platform_update`, `platform_execute`
        **Knowledge:** `discover`, `read_file`, `web_search`, `view_web_page`
        **Browser:** `browser_use` — Autonomous web browsing (navigate, click, type, scroll, screenshot). Supports user handoff for login.
        **Interface:** `load_canvas`, `ask_user`, `bash`
        **Memory:** `remember_this`, `recall_context`, `search_memory`, `list_saved`, `bookmark_this`
        
        ## Building Things (use platform_create)
        
        `platform_create` handles ALL creation — both simple data and complex builds:
        - **Landing page** → `platform_create(type: "landing_page", data: { title: "...", description: "..." })`
        - **Website** → `platform_create(type: "website", data: { name: "...", pages: [{ title: "...", description: "..." }] })`
        - **App/Module** → `platform_create(type: "app", data: { name: "CRM", description: "..." })`
        - **Workflow** → `platform_create(type: "workflow", data: { name: "...", trigger: "...", actions: [...] })`
        - **Contacts, campaigns, templates, etc.** → `platform_create(type: "contact", data: { ... })`
        
        ## Viewing Things (use load_canvas)
        - `landing_page_editor` — View/edit a landing page (pass landing_page_id)
        - `contact_viewer` — View and manage contacts
        - `pipeline_viewer` — Visual CRM pipeline
        - `automation_dashboard` — Monitor all automations
        - `my_creations` — View all created assets
        - `module_manager` — View installed apps
        
        ## CRITICAL: Tool Usage Rules
        
        **You MUST call tools to perform actions.** Never claim to have completed an action without a tool call.
        
        **Wrong:** Saying "Done! I created 10 contacts." without tool calls
        **Right:** Calling `platform_create` 10 times, THEN summarizing what was created
        
        **Wrong:** Outputting CSV as text and saying "copy this"
        **Right:** Using the `platform_execute` tool with action="generate_file"
        
        **Wrong:** Guessing at math calculations (LLMs are bad at math!)
        **Right:** Using the `bash` tool to run Python for calculations
        
        If asked to show/view something, use `load_canvas` to open the appropriate view.
        If unsure which tool to use, call `discover` first.
        
        **IMPORTANT:** Your current tool capabilities ALWAYS override anything you said in previous messages.
        If you previously said "I can't do X" but you now have a tool for it, USE THE TOOL.
      TOOLS
    end

    def build_learned_context
      # Pull in learned behaviors and memories (reuse existing infrastructure)
      parts = []

      # Scout personality (if configured)
      begin
        if entity&.respond_to?(:scout_personality) && entity.scout_personality.present?
          parts << "## Communication Style\n#{entity.scout_personality}"
        end
      rescue => e
        Rails.logger.debug "[V3::SystemPrompt] Personality error: #{e.message}"
      end

      # Learned behaviors from ScoutLearning (entity-level, not user-level)
      begin
        learnings = ScoutLearning.where(entity: entity)
                                 .where("confidence >= ?", 0.7)
                                 .where(active: true)
                                 .order(confidence: :desc)
                                 .limit(10)

        if learnings.any?
          learned = learnings.map { |l| "- #{l.learning}" }.join("\n")
          parts << "## Learned Preferences\n#{learned}"
        end
      rescue => e
        Rails.logger.debug "[V3::SystemPrompt] Learnings error: #{e.message}"
      end

      parts.compact.reject(&:blank?).join("\n\n")
    end
  end
end
