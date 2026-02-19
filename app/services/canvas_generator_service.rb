# frozen_string_literal: true

# CanvasGeneratorService
#
# Generates rich, data-bound canvas HTML/JS/CSS for module views.
# Uses Claude to create professional canvases that integrate with
# the existing module_canvas_controller.js Stimulus controller
# and the /api/modules/:slug/models/:model API.
#
# Usage:
#   service = CanvasGeneratorService.new(entity: entity, user: user)
#   result = service.generate(
#     app_module: module,
#     view_type: 'kanban',
#     fields: [...],
#     related_models: [...]
#   )
#   # => { html: "...", js: "...", css: "..." }
#
class CanvasGeneratorService
  # Use Claude for canvas generation
  CANVAS_MODEL_ID = "global.anthropic.claude-sonnet-4-6"
  MAX_TOKENS = 8192

  # View types that we can generate
  SUPPORTED_VIEW_TYPES = %w[list kanban form detail dashboard calendar freeform].freeze

  # Fallback: use static templates when AI generation fails or is unavailable
  STATIC_FALLBACK = true

  # Canvas quality validation: max issues before skipping AI fix pass
  # If more than this many issues found, the canvas is too broken for targeted fixes
  MAX_QUALITY_ISSUES_FOR_FIX = 10

  def initialize(entity:, user:)
    @entity = entity
    @user = user
  end

  # Generate canvas HTML/JS/CSS for a given module and view type
  #
  # @param app_module [AppModule] The module to generate for
  # @param view_type [String] One of: list, kanban, form, detail, dashboard, calendar, freeform
  # @param fields [Array<Hash>] Field definitions from the plan spec
  # @param related_models [Array<Hash>] Related models for parent/child display
  # @param description [String] Optional style/design hint from the user (used by freeform view type)
  # @return [Hash] { html: String, js: String, css: String }
  def generate(app_module:, view_type:, fields:, related_models: [], description: nil)
    view_type = view_type.to_s.downcase
    @description = description
    unless SUPPORTED_VIEW_TYPES.include?(view_type)
      Rails.logger.warn "[CanvasGenerator] Unsupported view type: #{view_type}, falling back to 'list'"
      view_type = 'list'
    end

    Rails.logger.info "[CanvasGenerator] Generating #{view_type} canvas for #{app_module.name}"

    # Try AI generation first
    begin
      result = generate_with_ai(app_module, view_type, fields, related_models)
      if result && result[:html].present?
        Rails.logger.info "[CanvasGenerator] AI generation successful for #{app_module.name}/#{view_type}"
        return result
      end
    rescue => e
      Rails.logger.warn "[CanvasGenerator] AI generation failed: #{e.message}, using static template"
    end

    # Fallback to static templates
    generate_static(app_module, view_type, fields, related_models)
  end

  private

  # ============================================
  # AI GENERATION
  # ============================================

  def generate_with_ai(app_module, view_type, fields, related_models)
    prompt = build_canvas_prompt(app_module, view_type, fields, related_models)

    response = bedrock_client.converse(
      model_id: CANVAS_MODEL_ID,
      messages: [{ role: "user", content: [{ text: prompt }] }],
      inference_config: { max_tokens: MAX_TOKENS, temperature: 0.3 },
      system: [{ text: canvas_system_prompt }]
    )

    raw_text = response.output.message.content
                       .select { |b| b.respond_to?(:text) && b.text }
                       .map(&:text)
                       .join("\n")

    result = parse_canvas_response(raw_text)

    # Quality validation: check for unwired buttons, dead links, etc.
    # If issues found, attempt an AI fix pass before returning
    validate_and_fix_canvas(result)
  end

  def canvas_system_prompt
    <<~PROMPT
      You are a UI code generator that creates professional, data-driven canvas views for business applications.

      OUTPUT FORMAT: Return ONLY three fenced code blocks in this exact order:
      1. ```html ... ``` — The canvas HTML
      2. ```javascript ... ``` — The canvas JavaScript
      3. ```css ... ``` — The canvas CSS

      Do NOT include any explanation text, just the three code blocks.

      TECHNICAL REQUIREMENTS:
      - Bootstrap 5 classes for all layout and styling (already loaded in parent page)
      - Lucide icons via <i data-lucide="icon-name"></i> (already loaded)
      - The Stimulus controller `module-canvas` is automatically connected to elements with data-controller="module-canvas"
      - Use data-action="click->module-canvas#performAction" with data-action-name="add|edit|refresh|export" for standard actions
      - For the JavaScript section, write a self-executing function that runs when the canvas is loaded
      - CRITICAL: Do NOT use document.addEventListener('DOMContentLoaded', ...) — the canvas loads dynamically after the page is already loaded, so DOMContentLoaded will never fire. Use setTimeout(function() { ... }, 100) instead.
      - CRITICAL: Do NOT use MutationObserver on document.body — this causes infinite loops when combined with lucide.createIcons() or any DOM-modifying code. If you need to re-initialize Lucide icons, call lucide.createIcons() once after rendering, not on every DOM change.
      - The API base path for data is: /api/modules/MODULE_SLUG/models/MODEL_NAME
        - GET / — list records (supports ?search=, ?status=, ?limit=, ?page=)
        - GET /:id — single record
        - POST / — create record (JSON body)
        - PATCH /:id — update record (JSON body)
        - DELETE /:id — delete record
        - GET /schema — get field definitions
      - All API calls must include headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content }
      - For modals, use Bootstrap 5 modal API (new bootstrap.Modal(...))
      - For charts, use Chart.js (loaded via CDN script tag in the JS section if needed)
      - For drag-and-drop kanban, use native HTML5 drag and drop API
      - Make everything responsive (mobile-friendly)

      DESIGN GUIDELINES:
      - Clean, modern, professional look
      - Card-based layouts with subtle shadows
      - Use Bootstrap color utilities (bg-primary, text-success, etc.)
      - Status badges with appropriate colors
      - Empty states with helpful messages
      - Loading spinners while data fetches
      - Toast notifications for actions (use existing showToast function if available, or create one)
      - Confirmation dialogs before destructive actions
    PROMPT
  end

  def build_canvas_prompt(app_module, view_type, fields, related_models)
    field_descriptions = fields.map do |f|
      name = f['name'] || f[:name]
      type = f['field_type'] || f['type'] || f[:type] || 'string'
      options = f['options'] || f[:options]
      required = f['required'] || f[:required]
      desc = "- #{name} (#{type})"
      desc += " [required]" if required
      desc += " options: #{options.join(', ')}" if options.present?
      desc
    end.join("\n")

    related_info = if related_models.present?
      models = related_models.map do |rm|
        rel_type = rm['relationship_type'] || rm[:relationship_type] || 'has_many'
        "- #{rm['name'] || rm[:name]} (#{rel_type})"
      end.join("\n")
      "\nRELATED MODELS:\n#{models}"
    else
      ''
    end

    model_name = app_module.slug.classify
    module_slug = app_module.slug

    <<~PROMPT
      Generate a #{view_type.upcase} canvas for "#{app_module.name}".

      MODULE SLUG: #{module_slug}
      MODEL NAME: #{model_name}
      API PATH: /api/modules/#{module_slug}/models/#{model_name}

      FIELDS:
      #{field_descriptions}
      #{related_info}

      VIEW TYPE: #{view_type}
      #{view_type_instructions(view_type, fields)}
    PROMPT
  end

  def view_type_instructions(view_type, fields)
    status_field = fields.find { |f| (f['name'] || f[:name]) == 'status' }
    status_options = status_field&.dig('options') || status_field&.dig(:options) || []

    case view_type
    when 'list'
      <<~INST
        Create a data grid/table view with:
        - Search bar at top
        - Sortable column headers (click to sort)
        - Row actions: Edit (pencil icon), Delete (trash icon)
        - "Add New" button in the header
        - Pagination at bottom
        - CSV export button
        - Show the first 6-8 most important fields as columns
        - Status columns should use colored badges
        - Date columns formatted nicely (e.g., "Feb 8, 2026")
      INST
    when 'kanban'
      columns = status_options.presence || %w[todo in_progress done]
      <<~INST
        Create a Kanban board with columns: #{columns.join(', ')}
        - Each column shows cards for records with that status
        - Cards show key fields (title/name, priority if present, assignee if present)
        - Drag and drop cards between columns to update status
        - Click card to open detail/edit modal
        - "Add" button on each column header
        - Card count badge on each column
        - Use HTML5 native drag and drop (dragstart, dragover, drop events)
      INST
    when 'form'
      <<~INST
        Create a form view for creating/editing records:
        - Clean form layout with proper labels
        - Field types: text inputs, textareas, select dropdowns, date pickers, number inputs, checkboxes
        - Validation indicators (required fields marked)
        - Submit and Cancel buttons
        - Support both create (empty form) and edit (pre-populated) modes
        - Show loading state on submit
        - Display success/error feedback
      INST
    when 'detail'
      <<~INST
        Create a detail view for viewing a single record:
        - Card-based layout showing all fields
        - Edit button to switch to inline editing
        - Back button to return to list
        - Show related records if any
        - Status displayed as a prominent badge
        - Timestamps shown in a clean format
        - Action buttons: Edit, Delete, Back to List
      INST
    when 'dashboard'
      <<~INST
        Create a dashboard view with:
        - Summary stat cards at top (Total Records, This Week, This Month, by Status)
        - A chart section (bar or doughnut chart showing records by status)
        - Recent records table (last 5 records)
        - Quick action buttons (Add New, View All, Export)
        - Use Chart.js for charts (include CDN in a <script> tag)
        - Auto-refresh data every 60 seconds
        - All stats fetched from the API
      INST
    when 'calendar'
      <<~INST
        Create a calendar view:
        - Monthly calendar grid
        - Events/records placed on their date field
        - Click on a date to create a new record
        - Click on an event to view/edit
        - Navigation: previous/next month
        - Today highlighted
        - Use the first date-type field as the calendar date
      INST
    when 'freeform'
      desc = @description.present? ? "\n\nUser's design intent: #{@description}" : ""
      <<~INST
        Create a custom, visually rich canvas for this module. You have FULL creative freedom
        over the layout, styling, and interaction design. Choose whatever UI pattern best fits
        the data — cards, grids, charts, timelines, split panels, or any combination.

        REQUIREMENTS:
        - Must include working CRUD operations (create, read, update, delete) via the API
        - All buttons and interactive elements must be wired to real actions
        - Use modals or inline forms for creating/editing records
        - Include search or filtering if appropriate for the data
        - Make it beautiful, modern, and highly functional
        - Include empty states, loading indicators, and error handling
        - Feel free to include Chart.js charts (via CDN script tag) if the data benefits from visualization#{desc}
      INST
    else
      "Create an appropriate view for this data."
    end
  end

  # ============================================
  # RESPONSE PARSING
  # ============================================

  def parse_canvas_response(raw_text)
    # Extract code blocks from the response
    html = extract_code_block(raw_text, 'html')
    js = extract_code_block(raw_text, 'javascript') || extract_code_block(raw_text, 'js')
    css = extract_code_block(raw_text, 'css')

    # If no labeled blocks found, try to split by generic code blocks
    if html.blank?
      blocks = raw_text.scan(/```\w*\s*\n(.*?)```/m).flatten
      html = blocks[0] if blocks[0]
      js = blocks[1] if blocks[1]
      css = blocks[2] if blocks[2]
    end

    {
      html: html&.strip,
      js: sanitize_canvas_js(js&.strip),
      css: css&.strip
    }
  end

  def sanitize_canvas_js(js)
    return js if js.blank?

    # Replace DOMContentLoaded with setTimeout since canvases load after page is ready
    js = js.gsub(
      /document\.addEventListener\s*\(\s*['"]DOMContentLoaded['"]\s*,\s*function\s*\(\s*\)\s*\{/,
      'setTimeout(function() {'
    )

    # Remove MutationObserver watching document.body (causes infinite loops with lucide.createIcons)
    js = js.gsub(
      /\/\/.*?(?:Re-initialize|re-initialize|reinitialize|Reinitialize).*?\n\s*(?:const|let|var)\s+\w+\s*=\s*new\s+MutationObserver\s*\(.*?\)\s*;\s*\n\s*\w+\.observe\s*\(\s*document\.body\s*,\s*\{[^}]*\}\s*\)\s*;/m,
      '// Initialize Lucide icons once after a short delay
  setTimeout(function() { if (typeof lucide !== "undefined") lucide.createIcons(); }, 100);'
    )

    # Catch any remaining MutationObserver on document.body even without the comment
    js = js.gsub(
      /(?:const|let|var)\s+(\w+)\s*=\s*new\s+MutationObserver\s*\(\s*function\s*\(\s*\w*\s*\)\s*\{\s*(?:initializeLucide|lucide\.createIcons)\s*\(\s*\)\s*;\s*\}\s*\)\s*;\s*\n\s*\1\.observe\s*\(\s*document\.body\s*,\s*\{[^}]*\}\s*\)\s*;/m,
      '// Initialize Lucide icons once after a short delay
  setTimeout(function() { if (typeof lucide !== "undefined") lucide.createIcons(); }, 100);'
    )

    js
  end

  def extract_code_block(text, language)
    # Match ```language\n...\n```
    match = text.match(/```#{language}\s*\n(.*?)```/m)
    match&.captures&.first
  end

  # ============================================
  # CANVAS QUALITY VALIDATION
  # ============================================

  # Orchestrator: validate generated canvas and attempt AI fix if issues found
  def validate_and_fix_canvas(result)
    return result if result[:html].blank?

    issues = analyze_canvas_quality(result[:html], result[:js])

    if issues.empty?
      Rails.logger.info "[CanvasGenerator] Quality check passed (0 issues)"
      return result
    end

    issue_summary = issues.group_by { |i| i[:type] }.transform_values(&:count)
    Rails.logger.warn "[CanvasGenerator] Quality check found #{issues.length} issue(s): #{issue_summary}"

    # Too many issues means the canvas is fundamentally broken — not worth patching
    if issues.length > MAX_QUALITY_ISSUES_FOR_FIX
      Rails.logger.warn "[CanvasGenerator] Too many issues (#{issues.length} > #{MAX_QUALITY_ISSUES_FOR_FIX}), skipping AI fix"
      return result
    end

    # Attempt targeted AI fix pass
    begin
      fixed = ai_fix_canvas_issues(result, issues)
      if fixed && fixed[:html].present?
        remaining = analyze_canvas_quality(fixed[:html], fixed[:js])
        resolved = issues.length - remaining.length

        if resolved > 0
          Rails.logger.info "[CanvasGenerator] AI fix resolved #{resolved}/#{issues.length} issues (#{remaining.length} remaining)"
          return fixed
        else
          Rails.logger.warn "[CanvasGenerator] AI fix did not improve quality, using original"
        end
      end
    rescue => e
      Rails.logger.warn "[CanvasGenerator] AI fix pass failed: #{e.message}, using original"
    end

    result
  end

  # Static analysis of canvas HTML + JS for common quality issues.
  # Returns an array of issue hashes, empty if no problems found.
  #
  # Checks:
  #   1. Buttons without any event handling (no onclick, data-action, submit type, or JS listener)
  #   2. Links with href="#" and no handler (dead links)
  #   3. Forms without submit handling
  #   4. Modal triggers (data-bs-target) pointing to non-existent modals
  #   5. onclick calls to functions not defined in the JavaScript
  #   6. JavaScript getElementById/querySelector references to IDs not in the HTML
  #
  def analyze_canvas_quality(html, js)
    issues = []
    return issues if html.blank?
    js = js.to_s

    # Collect all element IDs from the HTML for cross-referencing
    html_ids = Set.new(html.scan(/\bid\s*=\s*["']([^"']+)["']/i).flatten)

    # ── Check 1: Buttons without any event handling ──
    html.scan(/<button\b([^>]*)>/i).each do |(attrs)|
      next if attrs.match?(/data-action\s*=/i)           # Stimulus handler
      next if attrs.match?(/onclick\s*=/i)                # Inline handler
      next if attrs.match?(/type\s*=\s*["']submit["']/i)  # Form submit button
      next if attrs.match?(/data-bs-toggle\s*=/i)         # Bootstrap component (dropdown, modal, etc.)
      next if attrs.match?(/data-bs-dismiss\s*=/i)        # Bootstrap dismiss button

      # Check if button has an ID that's referenced in the JS (addEventListener pattern)
      id_match = attrs.match(/\bid\s*=\s*["']([^"']+)["']/i)
      next if id_match && js.include?(id_match[1])

      issues << { type: :unwired_button, detail: attrs.strip[0..100] }
    end

    # ── Check 2: Dead links (href="#" with no handler) ──
    html.scan(/<a\b([^>]*)>/i).each do |(attrs)|
      next unless attrs.match?(/href\s*=\s*["']#["']/i)  # Only flag href="#" links
      next if attrs.match?(/data-action\s*=/i)
      next if attrs.match?(/onclick\s*=/i)
      next if attrs.match?(/data-bs-toggle\s*=/i)         # Bootstrap component trigger

      id_match = attrs.match(/\bid\s*=\s*["']([^"']+)["']/i)
      next if id_match && js.include?(id_match[1])

      issues << { type: :dead_link, detail: attrs.strip[0..100] }
    end

    # ── Check 3: Forms without submit handling ──
    html.scan(/<form\b([^>]*)>/i).each do |(attrs)|
      next if attrs.match?(/data-action\s*=.*submit/i)    # Stimulus submit action
      next if attrs.match?(/onsubmit\s*=/i)               # Inline handler
      next if attrs.match?(/action\s*=\s*["'](?!#)[^"']/i) # Has a real action URL (not "#")

      id_match = attrs.match(/\bid\s*=\s*["']([^"']+)["']/i)
      next if id_match && js.include?(id_match[1])

      issues << { type: :unwired_form, detail: attrs.strip[0..100] }
    end

    # ── Check 4: Modal triggers without matching modal elements ──
    html.scan(/data-bs-target\s*=\s*["']#([^"']+)["']/i).each do |(modal_id)|
      next if html_ids.include?(modal_id)
      issues << { type: :missing_modal, modal_id: modal_id }
    end

    # ── Check 5: onclick functions not defined in the JavaScript ──
    html.scan(/onclick\s*=\s*["']([a-zA-Z_$][a-zA-Z0-9_$]*)\s*\(/i).each do |(func_name)|
      next if func_name == 'return'
      next if func_name.start_with?('window') # window.xxx() may be defined elsewhere

      func_pattern = /(?:function\s+#{Regexp.escape(func_name)}\b|#{Regexp.escape(func_name)}\s*[:=]\s*(?:function|async\s|\())/
      next if js.match?(func_pattern)

      issues << { type: :undefined_function, function: func_name }
    end

    # ── Check 6: DOMContentLoaded (never fires in dynamically loaded canvases) ──
    if js.match?(/document\.addEventListener\s*\(\s*['"]DOMContentLoaded['"]/i)
      issues << { type: :dom_content_loaded, detail: "DOMContentLoaded will never fire in dynamically loaded canvases — use setTimeout instead" }
    end

    # ── Check 7: MutationObserver on document.body (causes infinite loops with DOM-modifying callbacks) ──
    if js.match?(/MutationObserver/i) && js.match?(/document\.body/i)
      issues << { type: :mutation_observer_body, detail: "MutationObserver on document.body causes infinite loops when combined with DOM-modifying callbacks like lucide.createIcons()" }
    end

    # ── Check 8: JS references element IDs not present in HTML ──
    js_id_refs = Set.new(
      js.scan(/getElementById\s*\(\s*["']([^"']+)["']\s*\)/).flatten +
      js.scan(/querySelector\s*\(\s*["']#([^"']+)["']\s*\)/).flatten
    )

    js_id_refs.each do |ref_id|
      next if html_ids.include?(ref_id)
      # Skip IDs that appear multiple times in JS — likely created dynamically via innerHTML
      next if js.scan(/#{Regexp.escape(ref_id)}/).length > 1

      issues << { type: :missing_element, element_id: ref_id }
    end

    issues
  end

  # Make a focused AI call to fix the specific issues found by static analysis.
  # This is much cheaper and more reliable than regenerating from scratch because
  # the AI only needs to add/fix the missing pieces, not reinvent the whole canvas.
  def ai_fix_canvas_issues(result, issues)
    issue_list = issues.map.with_index do |issue, i|
      case issue[:type]
      when :unwired_button
        "#{i + 1}. UNWIRED BUTTON: <button #{issue[:detail]}> has no click handler — add an event listener or data-action"
      when :dead_link
        "#{i + 1}. DEAD LINK: <a #{issue[:detail]}> has href='#' with no handler — add a click handler or real navigation"
      when :unwired_form
        "#{i + 1}. UNWIRED FORM: <form #{issue[:detail]}> has no submit handler — add a submit event listener"
      when :missing_modal
        "#{i + 1}. MISSING MODAL: data-bs-target='##{issue[:modal_id]}' references a modal that doesn't exist — add the modal HTML"
      when :undefined_function
        "#{i + 1}. UNDEFINED FUNCTION: onclick calls '#{issue[:function]}()' but it's not defined — implement the function"
      when :missing_element
        "#{i + 1}. MISSING ELEMENT: JS references id='#{issue[:element_id]}' but no such element exists — add the element or fix the reference"
      when :dom_content_loaded
        "#{i + 1}. DOM_CONTENT_LOADED: Canvas uses DOMContentLoaded which never fires in dynamically loaded content — replace with setTimeout(function() { ... }, 100)"
      when :mutation_observer_body
        "#{i + 1}. MUTATION_OBSERVER_BODY: MutationObserver on document.body causes infinite loops — remove it and call lucide.createIcons() once after rendering instead"
      end
    end.compact

    fix_prompt = <<~PROMPT
      Fix the following #{issues.length} issue(s) in this canvas code. Each issue is an interactive element that is not properly wired up.

      ISSUES TO FIX:
      #{issue_list.join("\n")}

      CURRENT HTML:
      ```html
      #{result[:html]}
      ```

      CURRENT JAVASCRIPT:
      ```javascript
      #{result[:js]}
      ```

      #{result[:css].present? ? "CURRENT CSS:\n```css\n#{result[:css]}\n```" : ""}

      RULES:
      - Fix EVERY issue listed above — do not skip any
      - For unwired buttons: add JavaScript event listeners that perform a meaningful action
      - For dead links: add click handlers or proper navigation
      - For unwired forms: add submit event listeners with fetch API calls
      - For missing modals: add complete Bootstrap 5 modal HTML with form content
      - For undefined functions: implement the function with real functionality
      - For missing elements: add the element to HTML or fix the JS reference
      - Keep ALL existing functionality intact — do not remove or break anything
      - Return the COMPLETE fixed code (all three blocks, not just the changes)
    PROMPT

    response = bedrock_client.converse(
      model_id: CANVAS_MODEL_ID,
      messages: [{ role: "user", content: [{ text: fix_prompt }] }],
      inference_config: { max_tokens: MAX_TOKENS, temperature: 0.2 },
      system: [{ text: canvas_fix_system_prompt }]
    )

    raw_text = response.output.message.content
                       .select { |b| b.respond_to?(:text) && b.text }
                       .map(&:text)
                       .join("\n")

    parse_canvas_response(raw_text)
  end

  def canvas_fix_system_prompt
    <<~PROMPT
      You are a code quality fixer for business application canvases.
      You receive canvas code (HTML/JS/CSS) with specific identified issues and must fix ALL of them.

      OUTPUT FORMAT: Return ONLY three fenced code blocks in this exact order:
      1. ```html ... ``` — The complete fixed HTML
      2. ```javascript ... ``` — The complete fixed JavaScript
      3. ```css ... ``` — The complete fixed CSS

      Do NOT include any explanation text, just the three code blocks.

      TECHNICAL CONTEXT:
      - Bootstrap 5 is available (classes, modals, components)
      - Lucide icons via <i data-lucide="icon-name"></i>
      - Stimulus controller "module-canvas" handles data-action="click->module-canvas#performAction"
      - API base path: /api/modules/MODULE_SLUG/models/MODEL_NAME
      - CSRF token: document.querySelector('meta[name="csrf-token"]')?.content
      - Keep all existing working functionality intact
      - CRITICAL: Do NOT use document.addEventListener('DOMContentLoaded', ...) — canvases load dynamically after page load, so DOMContentLoaded never fires. Use setTimeout(function() { ... }, 100) instead.
      - CRITICAL: Do NOT use MutationObserver on document.body — causes infinite loops with lucide.createIcons().
    PROMPT
  end

  # ============================================
  # STATIC TEMPLATE FALLBACK
  # ============================================

  def generate_static(app_module, view_type, fields, related_models)
    case view_type
    when 'list'
      static_list_canvas(app_module, fields)
    when 'kanban'
      static_kanban_canvas(app_module, fields)
    when 'form'
      static_form_canvas(app_module, fields)
    when 'detail'
      static_detail_canvas(app_module, fields)
    when 'dashboard'
      static_dashboard_canvas(app_module, fields)
    when 'calendar'
      static_calendar_canvas(app_module, fields)
    when 'freeform'
      static_freeform_canvas(app_module, fields)
    else
      static_list_canvas(app_module, fields)
    end
  end

  def static_list_canvas(app_module, fields)
    display_fields = fields.first(7)
    model_name = app_module.slug.classify
    headers = display_fields.map { |f| "<th>#{(f['name'] || f[:name]).to_s.titleize}</th>" }.join("\n              ")
    field_names_js = display_fields.map { |f| "'#{f['name'] || f[:name]}'" }.join(', ')

    {
      html: <<~HTML,
        <div class="module-canvas p-4" data-controller="module-canvas" data-module-canvas-module-value="#{app_module.slug}" data-module-canvas-model-value="#{model_name}">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <div>
              <h4 class="mb-0">#{app_module.name}</h4>
              <small class="text-muted" id="record-count">Loading...</small>
            </div>
            <div class="d-flex gap-2">
              <div class="input-group" style="width: 250px;">
                <input type="text" class="form-control form-control-sm" placeholder="Search..." id="search-input">
                <button class="btn btn-outline-secondary btn-sm" id="search-btn"><i data-lucide="search" style="width:14px;height:14px"></i></button>
              </div>
              <button class="btn btn-outline-secondary btn-sm" id="export-btn"><i data-lucide="download" class="me-1" style="width:14px;height:14px"></i>Export</button>
              <button class="btn btn-primary btn-sm" data-action="click->module-canvas#performAction" data-action-name="add">
                <i data-lucide="plus" class="me-1" style="width:14px;height:14px"></i>Add New
              </button>
            </div>
          </div>
          <div class="card">
            <div class="table-responsive">
              <table class="table table-hover mb-0">
                <thead class="table-light">
                  <tr>
                    #{headers}
                    <th class="text-end" style="width:100px">Actions</th>
                  </tr>
                </thead>
                <tbody id="data-tbody">
                  <tr><td colspan="#{display_fields.length + 1}" class="text-center py-4"><div class="spinner-border spinner-border-sm text-muted" role="status"></div> Loading...</td></tr>
                </tbody>
              </table>
            </div>
          </div>
          <div class="d-flex justify-content-between align-items-center mt-3" id="pagination-area" style="display:none!important"></div>
        </div>
      HTML
      js: <<~JS,
        (function() {
          const moduleSlug = '#{app_module.slug}';
          const modelName = '#{model_name}';
          const apiBase = `/api/modules/${moduleSlug}/models/${modelName}`;
          const displayFields = [#{field_names_js}];
          const tbody = document.getElementById('data-tbody');
          const countEl = document.getElementById('record-count');

          function getHeaders() {
            return { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content };
          }

          async function loadData(search) {
            try {
              let url = apiBase + '?limit=50';
              if (search) url += '&search=' + encodeURIComponent(search);
              const resp = await fetch(url, { headers: getHeaders() });
              const data = await resp.json();
              const records = data.records || data.data || [];
              countEl.textContent = records.length + ' record(s)';
              renderRows(records);
            } catch(e) {
              tbody.innerHTML = '<tr><td colspan="#{display_fields.length + 1}" class="text-center py-4 text-danger">Failed to load data</td></tr>';
            }
          }

          function renderRows(records) {
            if (!records.length) {
              tbody.innerHTML = '<tr><td colspan="#{display_fields.length + 1}" class="text-center py-4 text-muted"><i data-lucide="inbox" style="width:24px;height:24px" class="mb-2 d-block mx-auto"></i>No records yet. Click "Add New" to get started.</td></tr>';
              if (window.lucide) lucide.createIcons();
              return;
            }
            tbody.innerHTML = records.map(r => {
              const cells = displayFields.map(f => {
                const val = r[f] ?? '';
                if (f === 'status' || f === 'priority') return '<td><span class="badge bg-' + statusColor(val) + '">' + val + '</span></td>';
                if (f.includes('date') || f.includes('_at')) return '<td>' + formatDate(val) + '</td>';
                return '<td>' + String(val).substring(0, 60) + '</td>';
              }).join('');
              return '<tr>' + cells + '<td class="text-end"><button class="btn btn-sm btn-outline-primary me-1" data-action="click->module-canvas#performAction" data-action-name="edit" data-record-id="' + r.id + '"><i data-lucide="pencil" style="width:12px;height:12px"></i></button><button class="btn btn-sm btn-outline-danger" data-action="click->module-canvas#performAction" data-action-name="delete" data-record-id="' + r.id + '"><i data-lucide="trash-2" style="width:12px;height:12px"></i></button></td></tr>';
            }).join('');
            if (window.lucide) lucide.createIcons();
          }

          function statusColor(s) {
            const map = { active:'success', completed:'success', done:'success', published:'success', open:'primary', in_progress:'warning', pending:'warning', todo:'secondary', draft:'secondary', closed:'dark', cancelled:'danger', blocked:'danger', urgent:'danger', high:'warning', medium:'info', low:'secondary' };
            return map[String(s).toLowerCase()] || 'secondary';
          }

          function formatDate(d) {
            if (!d) return '';
            try { return new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }); } catch(e) { return d; }
          }

          document.getElementById('search-btn')?.addEventListener('click', () => loadData(document.getElementById('search-input')?.value));
          document.getElementById('search-input')?.addEventListener('keydown', (e) => { if (e.key === 'Enter') loadData(e.target.value); });
          document.getElementById('export-btn')?.addEventListener('click', () => { window.open(apiBase + '?format=csv', '_blank'); });

          loadData();
        })();
      JS
      css: <<~CSS
        .module-canvas .badge { font-weight: 500; font-size: 0.75rem; }
        .module-canvas .table th { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em; color: #6c757d; }
        .module-canvas .table td { vertical-align: middle; font-size: 0.875rem; }
      CSS
    }
  end

  def static_kanban_canvas(app_module, fields)
    status_field = fields.find { |f| (f['name'] || f[:name]) == 'status' }
    columns = status_field&.dig('options') || status_field&.dig(:options) || %w[todo in_progress done]
    title_field = fields.find { |f| %w[title name subject].include?((f['name'] || f[:name]).to_s) }
    title_name = title_field ? (title_field['name'] || title_field[:name]) : 'name'
    model_name = app_module.slug.classify

    columns_html = columns.map.with_index do |col, i|
      <<~COL
        <div class="kanban-column flex-fill" data-status="#{col}" style="min-width: 250px; max-width: 350px;">
          <div class="card h-100">
            <div class="card-header d-flex justify-content-between align-items-center py-2">
              <span class="fw-semibold">#{col.titleize} <span class="badge bg-secondary ms-1 count-badge" id="count-#{col}">0</span></span>
              <button class="btn btn-sm btn-outline-primary" data-action="click->module-canvas#performAction" data-action-name="add" data-default-status="#{col}"><i data-lucide="plus" style="width:14px;height:14px"></i></button>
            </div>
            <div class="card-body p-2 kanban-drop-zone" data-status="#{col}" style="min-height: 200px; overflow-y: auto; max-height: 70vh;" id="col-#{col}">
              <div class="text-center text-muted py-3"><div class="spinner-border spinner-border-sm" role="status"></div></div>
            </div>
          </div>
        </div>
      COL
    end.join("\n")

    {
      html: <<~HTML,
        <div class="module-canvas p-4" data-controller="module-canvas" data-module-canvas-module-value="#{app_module.slug}" data-module-canvas-model-value="#{model_name}">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <h4 class="mb-0">#{app_module.name}</h4>
            <button class="btn btn-primary btn-sm" data-action="click->module-canvas#performAction" data-action-name="add">
              <i data-lucide="plus" class="me-1" style="width:14px;height:14px"></i>Add New
            </button>
          </div>
          <div class="d-flex gap-3 overflow-auto pb-3">
            #{columns_html}
          </div>
        </div>
      HTML
      js: <<~JS,
        (function() {
          const moduleSlug = '#{app_module.slug}';
          const modelName = '#{model_name}';
          const apiBase = `/api/modules/${moduleSlug}/models/${modelName}`;
          const titleField = '#{title_name}';
          const columns = #{columns.to_json};

          function getHeaders() {
            return { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content };
          }

          async function loadData() {
            try {
              const resp = await fetch(apiBase + '?limit=200', { headers: getHeaders() });
              const data = await resp.json();
              const records = data.records || data.data || [];
              columns.forEach(col => {
                const colRecords = records.filter(r => r.status === col);
                const container = document.getElementById('col-' + col);
                const countBadge = document.getElementById('count-' + col);
                if (countBadge) countBadge.textContent = colRecords.length;
                if (container) {
                  container.innerHTML = colRecords.map(r => createCard(r)).join('') || '<p class="text-muted text-center small py-3">No items</p>';
                }
              });
              setupDragAndDrop();
              if (window.lucide) lucide.createIcons();
            } catch(e) { console.error('Kanban load failed:', e); }
          }

          function createCard(record) {
            const title = record[titleField] || record.name || record.title || 'Untitled';
            const priority = record.priority ? '<span class="badge bg-' + priorityColor(record.priority) + ' me-1">' + record.priority + '</span>' : '';
            const assignee = record.assignee ? '<small class="text-muted"><i data-lucide="user" style="width:12px;height:12px" class="me-1"></i>' + record.assignee + '</small>' : '';
            return '<div class="card mb-2 kanban-card shadow-sm" draggable="true" data-id="' + record.id + '">' +
              '<div class="card-body p-2">' +
                '<div class="fw-semibold small">' + title + '</div>' +
                '<div class="mt-1">' + priority + assignee + '</div>' +
              '</div></div>';
          }

          function priorityColor(p) {
            const map = { urgent:'danger', high:'warning', medium:'info', low:'secondary' };
            return map[String(p).toLowerCase()] || 'secondary';
          }

          function setupDragAndDrop() {
            document.querySelectorAll('.kanban-card').forEach(card => {
              card.addEventListener('dragstart', e => {
                e.dataTransfer.setData('text/plain', card.dataset.id);
                card.classList.add('opacity-50');
              });
              card.addEventListener('dragend', () => card.classList.remove('opacity-50'));
              card.addEventListener('click', () => {
                const controller = document.querySelector('[data-controller="module-canvas"]')?.__stimulusController;
                if (controller) { controller.loadAndEditRecord(card.dataset.id); }
              });
            });
            document.querySelectorAll('.kanban-drop-zone').forEach(zone => {
              zone.addEventListener('dragover', e => { e.preventDefault(); zone.classList.add('bg-light'); });
              zone.addEventListener('dragleave', () => zone.classList.remove('bg-light'));
              zone.addEventListener('drop', async e => {
                e.preventDefault();
                zone.classList.remove('bg-light');
                const id = e.dataTransfer.getData('text/plain');
                const newStatus = zone.dataset.status;
                try {
                  await fetch(apiBase + '/' + id, { method: 'PATCH', headers: getHeaders(), body: JSON.stringify({ status: newStatus }) });
                  loadData();
                } catch(err) { console.error('Status update failed:', err); }
              });
            });
          }

          loadData();
        })();
      JS
      css: <<~CSS
        .kanban-card { cursor: grab; transition: box-shadow 0.15s; }
        .kanban-card:hover { box-shadow: 0 2px 8px rgba(0,0,0,0.12); }
        .kanban-card.opacity-50 { opacity: 0.5; }
        .kanban-drop-zone { transition: background-color 0.15s; }
        .kanban-drop-zone.bg-light { border: 2px dashed #0d6efd !important; }
      CSS
    }
  end

  def static_form_canvas(app_module, fields)
    model_name = app_module.slug.classify
    form_fields_html = fields.map do |f|
      name = (f['name'] || f[:name]).to_s
      type = (f['field_type'] || f['type'] || f[:type] || 'string').to_s
      label = name.titleize
      required = f['required'] || f[:required]
      options = f['options'] || f[:options]
      req_attr = required ? 'required' : ''

      case type
      when 'text'
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><textarea name='#{name}' class='form-control' rows='3' #{req_attr}></textarea></div>"
      when 'select'
        opts = (options || []).map { |o| "<option value='#{o}'>#{o.to_s.titleize}</option>" }.join
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><select name='#{name}' class='form-select' #{req_attr}><option value=''>Select...</option>#{opts}</select></div>"
      when 'boolean'
        "<div class='mb-3 form-check'><input type='checkbox' name='#{name}' class='form-check-input' id='field-#{name}'><label class='form-check-label' for='field-#{name}'>#{label}</label></div>"
      when 'date'
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><input type='date' name='#{name}' class='form-control' #{req_attr}></div>"
      when 'datetime'
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><input type='datetime-local' name='#{name}' class='form-control' #{req_attr}></div>"
      when 'integer'
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><input type='number' name='#{name}' class='form-control' #{req_attr}></div>"
      when 'decimal'
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><input type='number' step='0.01' name='#{name}' class='form-control' #{req_attr}></div>"
      else
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><input type='text' name='#{name}' class='form-control' #{req_attr}></div>"
      end
    end.join("\n        ")

    {
      html: <<~HTML,
        <div class="module-canvas p-4" data-controller="module-canvas" data-module-canvas-module-value="#{app_module.slug}" data-module-canvas-model-value="#{model_name}">
          <div class="card">
            <div class="card-header"><h5 class="mb-0">#{app_module.name.singularize} Form</h5></div>
            <div class="card-body">
              <form id="canvas-form">
                <input type="hidden" name="id" value="">
                #{form_fields_html}
                <div class="d-flex gap-2 mt-4 pt-3 border-top">
                  <button type="submit" class="btn btn-primary"><i data-lucide="save" class="me-1" style="width:14px;height:14px"></i>Save</button>
                  <button type="button" class="btn btn-outline-secondary" id="cancel-btn">Cancel</button>
                </div>
              </form>
            </div>
          </div>
        </div>
      HTML
      js: <<~JS,
        (function() {
          const moduleSlug = '#{app_module.slug}';
          const modelName = '#{model_name}';
          const apiBase = `/api/modules/${moduleSlug}/models/${modelName}`;
          const form = document.getElementById('canvas-form');

          function getHeaders() {
            return { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content };
          }

          form?.addEventListener('submit', async (e) => {
            e.preventDefault();
            const formData = new FormData(form);
            const data = {};
            formData.forEach((v, k) => { if (k !== 'id' && v !== '') data[k] = v; });
            const id = formData.get('id');
            const method = id ? 'PATCH' : 'POST';
            const url = id ? apiBase + '/' + id : apiBase;
            try {
              const resp = await fetch(url, { method, headers: getHeaders(), body: JSON.stringify(data) });
              if (resp.ok) {
                form.reset();
                form.querySelector('[name=id]').value = '';
                alert(id ? 'Updated successfully!' : 'Created successfully!');
              } else {
                const err = await resp.json();
                alert('Error: ' + (err.error || 'Save failed'));
              }
            } catch(e) { alert('Error: ' + e.message); }
          });

          document.getElementById('cancel-btn')?.addEventListener('click', () => {
            form.reset();
            form.querySelector('[name=id]').value = '';
          });
        })();
      JS
      css: <<~CSS
        .module-canvas .form-label { font-size: 0.875rem; }
        .module-canvas .form-control:focus, .module-canvas .form-select:focus { border-color: #0d6efd; box-shadow: 0 0 0 0.15rem rgba(13,110,253,.15); }
      CSS
    }
  end

  def static_detail_canvas(app_module, fields)
    model_name = app_module.slug.classify

    {
      html: <<~HTML,
        <div class="module-canvas p-4" data-controller="module-canvas" data-module-canvas-module-value="#{app_module.slug}" data-module-canvas-model-value="#{model_name}">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <h4 class="mb-0">#{app_module.name.singularize} Details</h4>
            <div class="d-flex gap-2">
              <button class="btn btn-sm btn-outline-primary" id="edit-btn"><i data-lucide="pencil" class="me-1" style="width:14px;height:14px"></i>Edit</button>
              <button class="btn btn-sm btn-outline-danger" id="delete-btn"><i data-lucide="trash-2" class="me-1" style="width:14px;height:14px"></i>Delete</button>
            </div>
          </div>
          <div class="card">
            <div class="card-body" id="detail-content">
              <p class="text-muted text-center py-4">Select a record to view details</p>
            </div>
          </div>
        </div>
      HTML
      js: <<~JS,
        (function() {
          const moduleSlug = '#{app_module.slug}';
          const modelName = '#{model_name}';
          const apiBase = `/api/modules/${moduleSlug}/models/${modelName}`;
          const detailContent = document.getElementById('detail-content');
          const fields = #{fields.map { |f| f['name'] || f[:name] }.to_json};
          let currentRecordId = null;

          function getHeaders() {
            return { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content };
          }

          window.loadRecordDetail = async function(id) {
            currentRecordId = id;
            try {
              const resp = await fetch(apiBase + '/' + id, { headers: getHeaders() });
              const record = await resp.json();
              const data = record.record || record.data || record;
              detailContent.innerHTML = fields.map(f => {
                const val = data[f] ?? '';
                return '<div class="row mb-2"><div class="col-sm-3 text-muted fw-semibold">' + f.replace(/_/g, ' ').replace(/\\b\\w/g, l => l.toUpperCase()) + '</div><div class="col-sm-9">' + val + '</div></div>';
              }).join('') + '<div class="row mb-2"><div class="col-sm-3 text-muted fw-semibold">Created</div><div class="col-sm-9">' + (data.created_at ? new Date(data.created_at).toLocaleString() : '-') + '</div></div>';
            } catch(e) { detailContent.innerHTML = '<p class="text-danger">Failed to load record</p>'; }
          };

          document.getElementById('edit-btn')?.addEventListener('click', () => {
            if (!currentRecordId) { alert('No record selected'); return; }
            const controller = document.querySelector('[data-controller="module-canvas"]')?.__stimulusController;
            if (controller) { controller.loadAndEditRecord(currentRecordId); }
          });

          document.getElementById('delete-btn')?.addEventListener('click', async () => {
            if (!currentRecordId) { alert('No record selected'); return; }
            if (!confirm('Are you sure you want to delete this record?')) return;
            try {
              await fetch(apiBase + '/' + currentRecordId, { method: 'DELETE', headers: getHeaders() });
              detailContent.innerHTML = '<p class="text-success text-center py-4">Record deleted</p>';
              currentRecordId = null;
            } catch(e) { alert('Delete failed: ' + e.message); }
          });
        })();
      JS
      css: <<~CSS
        .module-canvas .row.mb-2 { padding: 0.5rem 0; border-bottom: 1px solid #f0f0f0; }
        .module-canvas .row.mb-2:last-child { border-bottom: none; }
      CSS
    }
  end

  def static_dashboard_canvas(app_module, fields)
    model_name = app_module.slug.classify
    status_field = fields.find { |f| (f['name'] || f[:name]) == 'status' }
    has_status = status_field.present?

    {
      html: <<~HTML,
        <div class="module-canvas p-4">
          <h4 class="mb-4">#{app_module.name} Dashboard</h4>
          <div class="row mb-4">
            <div class="col-md-3"><div class="card border-0 shadow-sm"><div class="card-body text-center"><div class="text-muted small text-uppercase">Total</div><h2 class="mb-0" id="stat-total">--</h2></div></div></div>
            <div class="col-md-3"><div class="card border-0 shadow-sm"><div class="card-body text-center"><div class="text-muted small text-uppercase">This Week</div><h2 class="mb-0" id="stat-week">--</h2></div></div></div>
            <div class="col-md-3"><div class="card border-0 shadow-sm"><div class="card-body text-center"><div class="text-muted small text-uppercase">This Month</div><h2 class="mb-0" id="stat-month">--</h2></div></div></div>
            <div class="col-md-3"><div class="card border-0 shadow-sm"><div class="card-body text-center"><div class="text-muted small text-uppercase">Today</div><h2 class="mb-0" id="stat-today">--</h2></div></div></div>
          </div>
          #{has_status ? '<div class="row mb-4"><div class="col-md-6"><div class="card border-0 shadow-sm"><div class="card-header bg-transparent fw-semibold">By Status</div><div class="card-body"><canvas id="status-chart" height="200"></canvas></div></div></div><div class="col-md-6"><div class="card border-0 shadow-sm"><div class="card-header bg-transparent fw-semibold">Recent Records</div><div class="card-body p-0"><div class="table-responsive"><table class="table table-sm mb-0"><tbody id="recent-tbody"></tbody></table></div></div></div></div></div>' : '<div class="row mb-4"><div class="col-12"><div class="card border-0 shadow-sm"><div class="card-header bg-transparent fw-semibold">Recent Records</div><div class="card-body p-0"><div class="table-responsive"><table class="table table-sm mb-0"><tbody id="recent-tbody"></tbody></table></div></div></div></div></div>'}
        </div>
        <script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
      HTML
      js: <<~JS,
        (function() {
          const moduleSlug = '#{app_module.slug}';
          const modelName = '#{model_name}';
          const apiBase = `/api/modules/${moduleSlug}/models/${modelName}`;

          function getHeaders() {
            return { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content };
          }

          async function loadStats() {
            try {
              const resp = await fetch(`/api/modules/${moduleSlug}/stats`, { headers: getHeaders() });
              const stats = await resp.json();
              document.getElementById('stat-total').textContent = stats.total ?? '--';
              document.getElementById('stat-week').textContent = stats.this_week ?? '--';
              document.getElementById('stat-month').textContent = stats.this_month ?? '--';
              document.getElementById('stat-today').textContent = stats.today ?? '--';
            } catch(e) { console.error('Stats load failed:', e); }
          }

          async function loadRecent() {
            try {
              const resp = await fetch(apiBase + '?limit=5&order_by=created_at+desc', { headers: getHeaders() });
              const data = await resp.json();
              const records = data.records || data.data || [];
              const tbody = document.getElementById('recent-tbody');
              if (tbody) {
                tbody.innerHTML = records.map(r => {
                  const name = r.name || r.title || r.subject || 'Record #' + r.id;
                  const status = r.status ? '<span class="badge bg-secondary">' + r.status + '</span>' : '';
                  const date = r.created_at ? new Date(r.created_at).toLocaleDateString() : '';
                  return '<tr><td>' + name + '</td><td>' + status + '</td><td class="text-muted small">' + date + '</td></tr>';
                }).join('') || '<tr><td class="text-muted text-center">No records yet</td></tr>';
              }
            } catch(e) { console.error('Recent records load failed:', e); }
          }

          #{has_status ? "async function loadChart() { try { const resp = await fetch(apiBase + '?limit=500', { headers: getHeaders() }); const data = await resp.json(); const records = data.records || data.data || []; const statusCounts = {}; records.forEach(r => { statusCounts[r.status || 'unknown'] = (statusCounts[r.status || 'unknown'] || 0) + 1; }); const ctx = document.getElementById('status-chart'); if (ctx && window.Chart) { new Chart(ctx, { type: 'doughnut', data: { labels: Object.keys(statusCounts), datasets: [{ data: Object.values(statusCounts), backgroundColor: ['#0d6efd','#198754','#ffc107','#dc3545','#6c757d','#0dcaf0','#6610f2'] }] }, options: { responsive: true, plugins: { legend: { position: 'bottom' } } } }); } } catch(e) { console.error('Chart load failed:', e); } }" : ''}

          loadStats();
          loadRecent();
          #{has_status ? 'setTimeout(loadChart, 500);' : ''}
          setInterval(() => { loadStats(); loadRecent(); }, 60000);
        })();
      JS
      css: <<~CSS
        .module-canvas .card { transition: box-shadow 0.15s; }
        .module-canvas .card:hover { box-shadow: 0 4px 12px rgba(0,0,0,0.1); }
        .module-canvas h2 { font-size: 2rem; font-weight: 700; }
      CSS
    }
  end

  def static_calendar_canvas(app_module, fields)
    model_name = app_module.slug.classify
    date_field = fields.find { |f| %w[date datetime].include?((f['field_type'] || f['type'] || f[:type]).to_s) }
    date_name = date_field ? (date_field['name'] || date_field[:name]) : 'created_at'
    title_field = fields.find { |f| %w[title name subject].include?((f['name'] || f[:name]).to_s) }
    title_name = title_field ? (title_field['name'] || title_field[:name]) : 'name'

    {
      html: <<~HTML,
        <div class="module-canvas p-4" data-controller="module-canvas" data-module-canvas-module-value="#{app_module.slug}" data-module-canvas-model-value="#{model_name}">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <div class="d-flex align-items-center gap-2">
              <button class="btn btn-outline-secondary btn-sm" id="prev-month"><i data-lucide="chevron-left" style="width:14px;height:14px"></i></button>
              <h4 class="mb-0" id="month-title">Loading...</h4>
              <button class="btn btn-outline-secondary btn-sm" id="next-month"><i data-lucide="chevron-right" style="width:14px;height:14px"></i></button>
            </div>
            <button class="btn btn-primary btn-sm" data-action="click->module-canvas#performAction" data-action-name="add">
              <i data-lucide="plus" class="me-1" style="width:14px;height:14px"></i>Add New
            </button>
          </div>
          <div class="card border-0 shadow-sm"><div class="card-body p-0"><div id="calendar-grid"></div></div></div>
        </div>
      HTML
      js: <<~JS,
        (function() {
          const moduleSlug = '#{app_module.slug}';
          const modelName = '#{model_name}';
          const apiBase = `/api/modules/${moduleSlug}/models/${modelName}`;
          const dateField = '#{date_name}';
          const titleField = '#{title_name}';
          let currentDate = new Date();
          let records = [];

          function getHeaders() { return { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content }; }

          async function loadData() {
            try {
              const resp = await fetch(apiBase + '?limit=500', { headers: getHeaders() });
              const data = await resp.json();
              records = data.records || data.data || [];
              renderCalendar();
            } catch(e) { console.error('Calendar load failed:', e); }
          }

          function renderCalendar() {
            const year = currentDate.getFullYear();
            const month = currentDate.getMonth();
            document.getElementById('month-title').textContent = new Date(year, month).toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
            const firstDay = new Date(year, month, 1).getDay();
            const daysInMonth = new Date(year, month + 1, 0).getDate();
            const today = new Date();
            let html = '<table class="table table-bordered mb-0"><thead><tr>' + ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].map(d => '<th class="text-center small text-muted py-2">' + d + '</th>').join('') + '</tr></thead><tbody><tr>';
            for (let i = 0; i < firstDay; i++) html += '<td class="bg-light"></td>';
            for (let day = 1; day <= daysInMonth; day++) {
              const dateStr = year + '-' + String(month+1).padStart(2,'0') + '-' + String(day).padStart(2,'0');
              const isToday = today.getFullYear() === year && today.getMonth() === month && today.getDate() === day;
              const dayRecords = records.filter(r => r[dateField] && r[dateField].startsWith(dateStr));
              html += '<td class="' + (isToday ? 'bg-primary bg-opacity-10' : '') + '" style="vertical-align:top;min-height:80px;width:14.28%"><div class="small fw-semibold mb-1">' + day + '</div>';
              dayRecords.forEach(r => { html += '<div class="badge bg-primary text-truncate d-block mb-1" style="max-width:100%;cursor:pointer" title="' + (r[titleField] || '') + '">' + (r[titleField] || 'Event') + '</div>'; });
              html += '</td>';
              if ((firstDay + day) % 7 === 0 && day < daysInMonth) html += '</tr><tr>';
            }
            const remaining = (firstDay + daysInMonth) % 7;
            if (remaining > 0) for (let i = remaining; i < 7; i++) html += '<td class="bg-light"></td>';
            html += '</tr></tbody></table>';
            document.getElementById('calendar-grid').innerHTML = html;
          }

          document.getElementById('prev-month')?.addEventListener('click', () => { currentDate.setMonth(currentDate.getMonth() - 1); renderCalendar(); });
          document.getElementById('next-month')?.addEventListener('click', () => { currentDate.setMonth(currentDate.getMonth() + 1); renderCalendar(); });

          loadData();
        })();
      JS
      css: <<~CSS
        #calendar-grid td { height: 90px; font-size: 0.8rem; }
        #calendar-grid .badge { font-size: 0.7rem; font-weight: 500; }
      CSS
    }
  end

  def static_freeform_canvas(app_module, fields)
    model_name = app_module.slug.classify
    display_fields = fields.first(6)
    title_field = fields.find { |f| %w[title name subject].include?((f['name'] || f[:name]).to_s) }
    title_name = title_field ? (title_field['name'] || title_field[:name]) : 'name'
    status_field = fields.find { |f| (f['name'] || f[:name]) == 'status' }
    has_status = status_field.present?

    field_cards_html = display_fields.map do |f|
      name = (f['name'] || f[:name]).to_s
      "<div class=\"col-md-4 col-sm-6 mb-3\"><div class=\"card border-0 shadow-sm h-100\"><div class=\"card-body p-3\"><div class=\"text-muted small text-uppercase mb-1\">#{name.titleize}</div><div class=\"fw-semibold\" id=\"detail-#{name}\">--</div></div></div></div>"
    end.join("\n              ")

    {
      html: <<~HTML,
        <div class="module-canvas p-4" data-controller="module-canvas" data-module-canvas-module-value="#{app_module.slug}" data-module-canvas-model-value="#{model_name}">
          <div class="d-flex justify-content-between align-items-center mb-4">
            <div>
              <h4 class="mb-1">#{app_module.name}</h4>
              <small class="text-muted" id="record-count">Loading...</small>
            </div>
            <div class="d-flex gap-2">
              <div class="input-group" style="width: 220px;">
                <input type="text" class="form-control form-control-sm" placeholder="Search..." id="search-input">
                <button class="btn btn-outline-secondary btn-sm" id="search-btn"><i data-lucide="search" style="width:14px;height:14px"></i></button>
              </div>
              <button class="btn btn-primary btn-sm" data-action="click->module-canvas#performAction" data-action-name="add">
                <i data-lucide="plus" class="me-1" style="width:14px;height:14px"></i>Add New
              </button>
            </div>
          </div>

          <div class="row mb-4" id="stat-cards">
            <div class="col-md-3"><div class="card border-0 shadow-sm"><div class="card-body text-center py-3"><div class="text-muted small text-uppercase">Total</div><h3 class="mb-0 fw-bold" id="stat-total">--</h3></div></div></div>
            <div class="col-md-3"><div class="card border-0 shadow-sm"><div class="card-body text-center py-3"><div class="text-muted small text-uppercase">This Week</div><h3 class="mb-0 fw-bold" id="stat-week">--</h3></div></div></div>
            <div class="col-md-3"><div class="card border-0 shadow-sm"><div class="card-body text-center py-3"><div class="text-muted small text-uppercase">This Month</div><h3 class="mb-0 fw-bold" id="stat-month">--</h3></div></div></div>
            <div class="col-md-3"><div class="card border-0 shadow-sm"><div class="card-body text-center py-3"><div class="text-muted small text-uppercase">Today</div><h3 class="mb-0 fw-bold" id="stat-today">--</h3></div></div></div>
          </div>

          <div class="row" id="record-cards"></div>
        </div>
      HTML
      js: <<~JS,
        (function() {
          const moduleSlug = '#{app_module.slug}';
          const modelName = '#{model_name}';
          const apiBase = `/api/modules/${moduleSlug}/models/${modelName}`;
          const titleField = '#{title_name}';
          const displayFields = #{display_fields.map { |f| f['name'] || f[:name] }.to_json};

          function getHeaders() {
            return { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content };
          }

          async function loadStats() {
            try {
              const resp = await fetch(`/api/modules/${moduleSlug}/stats`, { headers: getHeaders() });
              const stats = await resp.json();
              document.getElementById('stat-total').textContent = stats.total ?? '--';
              document.getElementById('stat-week').textContent = stats.this_week ?? '--';
              document.getElementById('stat-month').textContent = stats.this_month ?? '--';
              document.getElementById('stat-today').textContent = stats.today ?? '--';
            } catch(e) { console.error('Stats load failed:', e); }
          }

          async function loadData(search) {
            const container = document.getElementById('record-cards');
            const countEl = document.getElementById('record-count');
            try {
              let url = apiBase + '?limit=50';
              if (search) url += '&search=' + encodeURIComponent(search);
              const resp = await fetch(url, { headers: getHeaders() });
              const data = await resp.json();
              const records = data.records || data.data || [];
              countEl.textContent = records.length + ' record(s)';
              if (!records.length) {
                container.innerHTML = '<div class="col-12 text-center py-5 text-muted"><i data-lucide="inbox" style="width:32px;height:32px" class="mb-2 d-block mx-auto"></i><p>No records yet. Click "Add New" to get started.</p></div>';
                if (window.lucide) lucide.createIcons();
                return;
              }
              container.innerHTML = records.map(r => {
                const title = r[titleField] || r.name || r.title || 'Record #' + r.id;
                const status = r.status ? '<span class="badge bg-' + statusColor(r.status) + '">' + r.status + '</span>' : '';
                const fields = displayFields.filter(f => f !== titleField && f !== 'status').slice(0, 3).map(f => {
                  const val = r[f] ?? '';
                  return '<div class="text-muted small text-truncate"><span class="fw-semibold">' + f.replace(/_/g, ' ') + ':</span> ' + String(val).substring(0, 40) + '</div>';
                }).join('');
                return '<div class="col-md-4 col-sm-6 mb-3"><div class="card border-0 shadow-sm h-100 record-card" data-id="' + r.id + '" style="cursor:pointer">' +
                  '<div class="card-body p-3"><div class="d-flex justify-content-between align-items-start mb-2"><h6 class="mb-0 fw-semibold">' + title + '</h6>' + status + '</div>' + fields +
                  '<div class="mt-2 pt-2 border-top d-flex gap-1"><button class="btn btn-sm btn-outline-primary flex-fill edit-btn" data-action="click->module-canvas#performAction" data-action-name="edit" data-record-id="' + r.id + '"><i data-lucide="pencil" style="width:12px;height:12px"></i> Edit</button>' +
                  '<button class="btn btn-sm btn-outline-danger delete-btn" data-action="click->module-canvas#performAction" data-action-name="delete" data-record-id="' + r.id + '"><i data-lucide="trash-2" style="width:12px;height:12px"></i></button></div></div></div></div>';
              }).join('');
              if (window.lucide) lucide.createIcons();
            } catch(e) {
              container.innerHTML = '<div class="col-12 text-center py-4 text-danger">Failed to load data</div>';
            }
          }

          function statusColor(s) {
            const map = { active:'success', completed:'success', done:'success', published:'success', open:'primary', in_progress:'warning', pending:'warning', todo:'secondary', draft:'secondary', closed:'dark', cancelled:'danger', blocked:'danger', urgent:'danger', high:'warning', medium:'info', low:'secondary' };
            return map[String(s).toLowerCase()] || 'secondary';
          }

          document.getElementById('search-btn')?.addEventListener('click', () => loadData(document.getElementById('search-input')?.value));
          document.getElementById('search-input')?.addEventListener('keydown', (e) => { if (e.key === 'Enter') loadData(e.target.value); });

          loadStats();
          loadData();
        })();
      JS
      css: <<~CSS
        .module-canvas .record-card { transition: box-shadow 0.15s, transform 0.15s; }
        .module-canvas .record-card:hover { box-shadow: 0 4px 12px rgba(0,0,0,0.1); transform: translateY(-2px); }
        .module-canvas .badge { font-weight: 500; font-size: 0.7rem; }
        .module-canvas h3 { font-size: 1.75rem; }
      CSS
    }
  end

  # ============================================
  # AWS BEDROCK CLIENT
  # ============================================

  def bedrock_client
    @bedrock_client ||= Aws::BedrockRuntime::Client.new(
      region: ENV["AWS_REGION"] || "us-east-1",
      http_read_timeout: 120,
      http_open_timeout: 30
    )
  end
end
