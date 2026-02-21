# frozen_string_literal: true

# DynamicContextService - Computes context and guidance for Amos dynamically
#
# Replaces the loadout-centric PluginInjectionService with a simpler,
# more intelligent approach:
#
# 1. Detect task type from canvas + message
# 2. Get relevant guidance from GuidanceLibrary
# 3. Select appropriate tools
# 4. Build context injection
#
# No pre-defined loadouts, no trigger configs, no keyword matching.
# Everything is computed on-the-fly based on what the user is doing.
#
# Usage:
#   service = DynamicContextService.new(user: user, entity: entity)
#   context = service.build_context(
#     canvas_context: { type: 'landing_page_editor', landing_page_id: 123 },
#     message: "Change the hero background color"
#   )
#   # Returns:
#   # {
#   #   task_type: :landing_page_edit,
#   #   guidance_block: "## CURRENT FOCUS: Landing Page Editing\n...",
#   #   priority_tools: ["edit_landing_page_section", ...],
#   #   context_summary: "Editing landing page 'My Page'"
#   # }
#
class DynamicContextService
  attr_reader :user, :entity

  def initialize(user:, entity:)
    @user = user
    @entity = entity
  end

  # Main entry point: Build dynamic context for Amos
  def build_context(canvas_context: nil, message: nil, intent: nil)
    # Step 1: Detect task type
    task_type = GuidanceLibrary.detect_task_type(
      canvas_context: canvas_context,
      message: message
    )

    Rails.logger.info "🎯 [DynamicContext] Detected task type: #{task_type}"

    # Step 2: Get guidance for this task type (includes learned experiences if available)
    guidance_block = GuidanceLibrary.for_task(task_type, context: canvas_context || {}, entity: @entity)
    
    # Step 2b: Inject additional context based on task type
    if task_type == :integration_setup
      integration_context = build_integration_context
      if integration_context.present?
        guidance_block = guidance_block + "\n\n" + integration_context
      end
    end

    # Step 3: Inject relevant skills from SkillLibraryService
    # Skills are matched by: integration name mentions, task keywords, custom use_when conditions
    skill_result = discover_skills_for_message(message, canvas_context)
    if skill_result
      guidance_block = guidance_block.to_s + "\n\n" + skill_result[:skill_block]
      Rails.logger.info "📚 [DynamicContext] Injected skills: #{skill_result[:skill_names].join(', ')}"

      # Track skill injections for the feedback loop (used by SkillEvolutionService)
      track_skill_injections(skill_result)
    end

    # Step 4: Get priority tools for this task type
    priority_tools = GuidanceLibrary.tools_for_task(task_type)

    # Step 5: Build context summary for logging/debugging
    context_summary = build_context_summary(task_type, canvas_context)

    # Step 6: Get entity's custom tools (always prioritize these)
    custom_tools = get_entity_custom_tools

    # Step 7: Get model recommendation based on learned performance data
    recommended_model = GuidanceLibrary.recommended_model_for(task_type, @entity)

    {
      task_type: task_type,
      guidance_block: guidance_block,
      priority_tools: (custom_tools + priority_tools).uniq,
      context_summary: context_summary,
      canvas_context: canvas_context,
      recommended_model: recommended_model,
      # For backwards compatibility with existing code
      plugin: nil,
      plugin_slug: nil,
      plugin_name: task_type.to_s.titleize,
      prompt_block: guidance_block,
      tools: [],  # Tools are selected separately
      tool_names: priority_tools,
      injection_reason: "Dynamic: #{task_type}"
    }
  end

  # Simplified tool selection based on task type
  def select_tools_for_task(task_type, base_tools: [])
    priority_tools = GuidanceLibrary.tools_for_task(task_type)
    custom_tools = get_entity_custom_tools

    # Order: Custom tools first, then priority tools, then base tools
    all_tools = (custom_tools + priority_tools + base_tools).uniq

    Rails.logger.info "🔧 [DynamicContext] Tools: #{custom_tools.length} custom + #{priority_tools.length} priority + #{base_tools.length} base = #{all_tools.length} total"

    all_tools
  end

  # Check if we have any meaningful context to inject
  def has_context?(canvas_context: nil, message: nil)
    task_type = GuidanceLibrary.detect_task_type(
      canvas_context: canvas_context,
      message: message
    )
    
    task_type != :general
  end

  private

  # Discover relevant skills based on the user's message
  # Detects integration names, task keywords, and matches custom uploaded skills
  def discover_skills_for_message(message, canvas_context)
    return nil if message.blank?

    # Detect integration names mentioned in the message
    integrations = detect_integration_names(message)

    SkillLibraryService.discover_skills(
      message: message,
      entity: @entity,
      integrations: integrations,
      canvas_context: canvas_context,
      limit: 3
    )
  rescue => e
    Rails.logger.warn "[DynamicContext] Skill discovery failed: #{e.message}"
    nil
  end

  # Extract integration names mentioned in the user's message
  INTEGRATION_NAME_PATTERNS = {
    'stripe'     => /\bstripe\b/i,
    'quickbooks' => /\bquickbooks\b|\bqbo\b|\bqb\b/i,
    'hubspot'    => /\bhubspot\b/i,
    'mailgun'    => /\bmailgun\b/i,
    'trello'     => /\btrello\b/i,
    'godaddy'    => /\bgodaddy\b|\bgo\s*daddy\b/i,
    'gmail'      => /\bgmail\b/i,
    'google_drive' => /\bgoogle\s*drive\b|\bgdrive\b/i,
    'google_sheets' => /\bgoogle\s*sheets?\b/i,
    'slack'      => /\bslack\b/i,
    'shopify'    => /\bshopify\b/i,
    'neon_crm'   => /\bneon\s*crm\b|\bneon\b/i,
  }.freeze

  def detect_integration_names(message)
    return [] if message.blank?

    msg = message.downcase
    INTEGRATION_NAME_PATTERNS.filter_map do |name, pattern|
      name if msg.match?(pattern)
    end
  end

  # Track which skills were injected for the evolution feedback loop
  def track_skill_injections(skill_result)
    return unless @entity.present? && @user.present?

    skill_result[:skills]&.each do |skill_data|
      skill_id = skill_data[:system_skill_id]
      next unless skill_id

      skill = SystemSkill.find_by(id: skill_id)
      next unless skill

      skill.record_injection!(
        entity: @entity,
        user: @user,
        session_id: Thread.current[:scout_session_id] || SecureRandom.hex(8),
        reason: skill_data[:type].to_s
      )
    end
  rescue => e
    Rails.logger.debug "[DynamicContext] Skill injection tracking failed: #{e.message}"
  end

  def build_context_summary(task_type, canvas_context)
    return "General assistance" if task_type == :general

    parts = ["Task: #{task_type.to_s.titleize}"]

    if canvas_context.present?
      canvas_type = canvas_context[:type] || canvas_context['type']
      parts << "Canvas: #{canvas_type}" if canvas_type

      # Add specific entity info
      if canvas_context[:landing_page_id] || canvas_context['landing_page_id']
        lp_id = canvas_context[:landing_page_id] || canvas_context['landing_page_id']
        lp = LandingPage.find_by(id: lp_id)
        parts << "Landing Page: #{lp&.title || lp_id}"
      end

      if canvas_context[:workflow_id] || canvas_context['workflow_id']
        parts << "Workflow: #{canvas_context[:workflow_id] || canvas_context['workflow_id']}"
      end
    end

    parts.join(" | ")
  end

  def get_entity_custom_tools
    return [] unless @entity.present?

    ToolDefinition.where(entity_id: @entity.id)
                  .where("is_public = true OR created_by_id = ?", @user&.id)
                  .pluck(:name)
  end

  # Build a compact summary of connected integrations.
  # Lists integration names and available action names only — the model
  # can call platform_query(type: "integration_actions") for full schemas
  # when needed, rather than bloating every prompt with input details.
  def build_integration_context
    return nil unless @entity.present? && @user.present?

    connections = Connection.where(user: @user, entity: @entity)
                            .active
                            .includes(:integration)
                            .order(created_at: :desc)
                            .limit(10)

    return nil if connections.empty?

    parts = ["## YOUR CONNECTED INTEGRATIONS"]
    parts << "Use `platform_execute(action: \"integration\", integration: \"slug\", operation: \"action_name\", inputs: {...})` to call these."
    parts << "Use `platform_query(type: \"integration_actions\", filters: { integration: \"slug\" })` to see full input schemas.\n"

    connections.each do |conn|
      integration = conn.integration
      next unless integration

      actions = IntegrationAction.for_entity(@entity)
                                 .where(integration: integration)
                                 .usable
                                 .limit(15)

      if actions.any?
        action_names = actions.map { |a| "`#{a.action_name}`" }.join(", ")
        parts << "- **#{integration.name}** (`#{integration.slug}`): #{action_names}"
      else
        parts << "- **#{integration.name}** (`#{integration.slug}`): _use platform_query to discover actions_"
      end
    end

    parts.join("\n")
  rescue => e
    Rails.logger.warn "[DynamicContext] Failed to build integration context: #{e.message}"
    nil
  end

  # Check if we have knowledge base docs for an integration
  def has_integration_knowledge?(integration_slug)
    return false unless integration_slug.present?
    
    # Check for system integration knowledge store
    store = RagStore.find_by(app_name: 'integration_knowledge', store_type: 'system')
    return false unless store
    
    # Check if docs exist for this integration
    store.rag_documents.exists?(original_filename: "#{integration_slug}.md")
  rescue
    false
  end
end
