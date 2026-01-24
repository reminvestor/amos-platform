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

    # Step 2: Get guidance for this task type
    guidance_block = GuidanceLibrary.for_task(task_type, context: canvas_context || {})

    # Step 3: Get priority tools for this task type
    priority_tools = GuidanceLibrary.tools_for_task(task_type)

    # Step 4: Build context summary for logging/debugging
    context_summary = build_context_summary(task_type, canvas_context)

    # Step 5: Get entity's custom tools (always prioritize these)
    custom_tools = get_entity_custom_tools

    {
      task_type: task_type,
      guidance_block: guidance_block,
      priority_tools: (custom_tools + priority_tools).uniq,
      context_summary: context_summary,
      canvas_context: canvas_context,
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
end
