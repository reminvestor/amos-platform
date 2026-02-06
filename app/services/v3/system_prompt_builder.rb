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
      tz = user&.timezone || "America/Los_Angeles"
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
                  "The user is viewing a landing page in the editor. Help them edit sections, content, and styling."
                when "design_studio"
                  "The user is in the Design Studio working on a design plan. Help them refine and build their design."
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
        ## How to Work (V3 Power Tools)
        
        You have 10 core tools. Use them directly — no need to search for specialized tools.
        
        **Data operations:**
        - `platform_query` — Read ANY data (contacts, campaigns, schemas, stats, integrations)
        - `platform_create` — Create ANY object (contact, campaign, template, etc.)
        - `platform_update` — Update ANY object by type + ID
        - `platform_execute` — Execute operations (send campaigns, run integrations, publish pages)
        
        **Knowledge:**
        - `discover` — Find skills, integrations, features, recipes
        - `read_file` — Read uploaded documents and knowledge base
        - `web_search` — Search the web for real-time information
        
        **Power tools:**
        - `bash` — Run shell commands (curl, jq, ruby, data processing)
        - `load_canvas` — Show visual content to the user
        - `ask_user` — Ask the user a clarifying question
        
        **Memory tools:** remember_this, recall_context, search_memory, list_saved, bookmark_this
        
        **Rules:**
        - Use `platform_query(type: "schema")` to discover what's available
        - Use `discover` when you need to learn HOW to do something
        - Use `bash` for anything not covered by other tools (calculations, API testing, data transforms)
        - Always scope queries to the current organization (automatic)
        - For destructive operations, confirm with the user first using `ask_user`
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

      # Learned behaviors from ScoutLearning
      begin
        learnings = ScoutLearning.where(user: user, entity: entity)
                                 .where("confidence >= ?", 0.7)
                                 .order(confidence: :desc)
                                 .limit(10)

        if learnings.any?
          learned = learnings.map { |l| "- #{l.learning_text}" }.join("\n")
          parts << "## Learned Preferences\n#{learned}"
        end
      rescue => e
        Rails.logger.debug "[V3::SystemPrompt] Learnings error: #{e.message}"
      end

      parts.compact.reject(&:blank?).join("\n\n")
    end
  end
end
