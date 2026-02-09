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
  CANVAS_MODEL_ID = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
  MAX_TOKENS = 8192

  # View types that we can generate
  SUPPORTED_VIEW_TYPES = %w[list kanban form detail dashboard calendar].freeze

  # Fallback: use static templates when AI generation fails or is unavailable
  STATIC_FALLBACK = true

  def initialize(entity:, user:)
    @entity = entity
    @user = user
  end

  # Generate canvas HTML/JS/CSS for a given module and view type
  #
  # @param app_module [AppModule] The module to generate for
  # @param view_type [String] One of: list, kanban, form, detail, dashboard, calendar
  # @param fields [Array<Hash>] Field definitions from the plan spec
  # @param related_models [Array<Hash>] Related models for parent/child display
  # @return [Hash] { html: String, js: String, css: String }
  def generate(app_module:, view_type:, fields:, related_models: [])
    view_type = view_type.to_s.downcase
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

    parse_canvas_response(raw_text)
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
      js: js&.strip,
      css: css&.strip
    }
  end

  def extract_code_block(text, language)
    # Match ```language\n...\n```
    match = text.match(/```#{language}\s*\n(.*?)```/m)
    match&.captures&.first
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

          function getHeaders() {
            return { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content };
          }

          window.loadRecordDetail = async function(id) {
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
