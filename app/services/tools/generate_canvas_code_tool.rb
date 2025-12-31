# frozen_string_literal: true

# GenerateCanvasCodeTool
#
# Platform Factory tool that generates HTML/JS canvas code
# for module views.
#
class Tools::GenerateCanvasCodeTool < Tools::BaseTool
  def self.metadata
    {
      name: 'generate_canvas_code',
      description: 'Generates HTML and JavaScript code for a module canvas view. Creates dashboard, data grid, or form canvases.',
      category: 'platform_factory',
      input_schema: {
        type: 'object',
        properties: {
          module_slug: {
            type: 'string',
            description: 'Slug of the module this canvas belongs to'
          },
          canvas_name: {
            type: 'string',
            description: 'Name of the canvas (e.g., "Product List", "Inventory Dashboard")'
          },
          canvas_type: {
            type: 'string',
            enum: %w[dashboard data_grid form report],
            description: 'Type of canvas to generate'
          },
          model_name: {
            type: 'string',
            description: 'Primary model this canvas displays (optional)'
          },
          fields_to_display: {
            type: 'array',
            items: { type: 'string' },
            description: 'Fields to show in the canvas'
          },
          actions: {
            type: 'array',
            items: { 
              type: 'object',
              properties: {
                name: { type: 'string' },
                icon: { type: 'string' },
                action: { type: 'string' }
              }
            },
            description: 'Available actions on this canvas'
          },
          ui_mode: {
            type: 'string',
            enum: %w[simple advanced],
            description: 'UI complexity mode'
          }
        },
        required: %w[module_slug canvas_name canvas_type]
      }
    }
  end

  def execute(args)
    log_execution(args)

    module_slug = get_arg(args, :module_slug)
    canvas_name = get_arg(args, :canvas_name)
    canvas_type = get_arg(args, :canvas_type, 'dashboard')
    model_name = get_arg(args, :model_name)
    fields_to_display = get_arg(args, :fields_to_display, [])
    actions = get_arg(args, :actions, [])
    ui_mode = get_arg(args, :ui_mode, 'simple')

    return error_response('Module slug is required') if module_slug.blank?
    return error_response('Canvas name is required') if canvas_name.blank?

    # Find the module
    app_module = AppModule.find_by(entity: entity, slug: module_slug)
    return error_response("Module not found: #{module_slug}") unless app_module

    # Generate the canvas code
    canvas_slug = canvas_name.parameterize.underscore
    html_content = generate_html(canvas_type, canvas_name, model_name, fields_to_display, actions, app_module)
    js_content = generate_js(canvas_type, canvas_slug, model_name, app_module)
    css_content = generate_css(canvas_type, canvas_slug)

    # Create the ModuleCanvas record
    canvas = ModuleCanvas.find_or_initialize_by(
      app_module: app_module,
      entity: entity,
      slug: canvas_slug
    )

    canvas.update!(
      name: canvas_name,
      canvas_type: canvas_type,
      ui_mode: ui_mode,
      html_content: html_content,
      js_content: js_content,
      css_content: css_content,
      data_sources: build_data_sources(model_name),
      actions: normalize_actions(actions)
    )

    # Update module components
    canvases = app_module.canvases_list
    canvases << canvas_slug unless canvases.include?(canvas_slug)
    app_module.update!(components: app_module.components.merge('canvases' => canvases))

    success_response(
      canvas_id: canvas.id,
      canvas_slug: canvas_slug,
      canvas_type: canvas_type,
      html_content: html_content,
      js_content: js_content,
      message: "Generated #{canvas_type} canvas: #{canvas_name}",
      next_step: 'Use register_module_canvas to make it available in the UI'
    )
  end

  private

  def generate_html(canvas_type, canvas_name, model_name, fields, actions, app_module)
    case canvas_type
    when 'dashboard'
      generate_dashboard_html(canvas_name, model_name, actions, app_module)
    when 'data_grid'
      generate_data_grid_html(canvas_name, model_name, fields, actions, app_module)
    when 'form'
      generate_form_html(canvas_name, model_name, fields, app_module)
    when 'report'
      generate_report_html(canvas_name, model_name, app_module)
    else
      generate_dashboard_html(canvas_name, model_name, actions, app_module)
    end
  end

  def generate_dashboard_html(canvas_name, model_name, actions, app_module)
    action_buttons = actions.map do |action|
      icon = action[:icon] || action['icon'] || 'plus'
      name = action[:name] || action['name'] || 'Action'
      action_id = action[:action] || action['action'] || name.parameterize
      
      <<~HTML
        <button type="button" class="btn btn-primary btn-sm" data-action="#{action_id}">
          <i data-lucide="#{icon}"></i> #{name}
        </button>
      HTML
    end.join("\n")

    <<~HTML
      <div class="module-dashboard" data-module="#{app_module.slug}" data-controller="module-canvas">
        <!-- Header -->
        <div class="dashboard-header d-flex justify-content-between align-items-center mb-4">
          <div>
            <h2 class="mb-1">#{canvas_name}</h2>
            <p class="text-muted mb-0">#{app_module.description || "Manage your #{model_name || 'data'}"}</p>
          </div>
          <div class="dashboard-actions d-flex gap-2">
            #{action_buttons}
          </div>
        </div>

        <!-- Stats Cards -->
        <div class="row mb-4">
          <div class="col-md-3">
            <div class="card stats-card">
              <div class="card-body">
                <div class="d-flex justify-content-between">
                  <div>
                    <h6 class="text-muted mb-1">Total</h6>
                    <h3 class="mb-0" data-stat="total">--</h3>
                  </div>
                  <div class="stats-icon bg-primary-subtle">
                    <i data-lucide="box"></i>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <div class="col-md-3">
            <div class="card stats-card">
              <div class="card-body">
                <div class="d-flex justify-content-between">
                  <div>
                    <h6 class="text-muted mb-1">This Week</h6>
                    <h3 class="mb-0" data-stat="this-week">--</h3>
                  </div>
                  <div class="stats-icon bg-success-subtle">
                    <i data-lucide="trending-up"></i>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <div class="col-md-3">
            <div class="card stats-card">
              <div class="card-body">
                <div class="d-flex justify-content-between">
                  <div>
                    <h6 class="text-muted mb-1">Active</h6>
                    <h3 class="mb-0" data-stat="active">--</h3>
                  </div>
                  <div class="stats-icon bg-info-subtle">
                    <i data-lucide="activity"></i>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <div class="col-md-3">
            <div class="card stats-card">
              <div class="card-body">
                <div class="d-flex justify-content-between">
                  <div>
                    <h6 class="text-muted mb-1">Alerts</h6>
                    <h3 class="mb-0" data-stat="alerts">--</h3>
                  </div>
                  <div class="stats-icon bg-warning-subtle">
                    <i data-lucide="alert-triangle"></i>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Main Content -->
        <div class="row">
          <div class="col-md-8">
            <div class="card">
              <div class="card-header d-flex justify-content-between align-items-center">
                <h5 class="mb-0">Recent Activity</h5>
                <button class="btn btn-link btn-sm">View All</button>
              </div>
              <div class="card-body">
                <div class="activity-list" data-target="activity">
                  <p class="text-muted">Loading activity...</p>
                </div>
              </div>
            </div>
          </div>
          <div class="col-md-4">
            <div class="card">
              <div class="card-header">
                <h5 class="mb-0">Quick Actions</h5>
              </div>
              <div class="card-body">
                <div class="d-grid gap-2">
                  <button class="btn btn-outline-primary" data-action="quick-add">
                    <i data-lucide="plus-circle"></i> Add New
                  </button>
                  <button class="btn btn-outline-secondary" data-action="quick-search">
                    <i data-lucide="search"></i> Search
                  </button>
                  <button class="btn btn-outline-info" data-action="quick-report">
                    <i data-lucide="file-text"></i> Generate Report
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    HTML
  end

  def generate_data_grid_html(canvas_name, model_name, fields, actions, app_module)
    # Generate table headers
    headers = fields.map do |field|
      field_name = field.is_a?(Hash) ? (field[:name] || field['name']) : field
      "<th>#{field_name.to_s.titleize}</th>"
    end.join("\n            ")

    <<~HTML
      <div class="module-data-grid" data-module="#{app_module.slug}" data-controller="module-data-grid">
        <!-- Toolbar -->
        <div class="grid-toolbar d-flex justify-content-between align-items-center mb-3">
          <div class="d-flex gap-2">
            <div class="input-group" style="width: 300px;">
              <span class="input-group-text"><i data-lucide="search"></i></span>
              <input type="text" class="form-control" placeholder="Search..." data-target="search">
            </div>
            <div class="dropdown">
              <button class="btn btn-outline-secondary dropdown-toggle" data-bs-toggle="dropdown">
                <i data-lucide="filter"></i> Filter
              </button>
              <ul class="dropdown-menu" data-target="filters">
                <li><a class="dropdown-item" href="#" data-filter="all">All</a></li>
                <li><a class="dropdown-item" href="#" data-filter="active">Active</a></li>
                <li><a class="dropdown-item" href="#" data-filter="inactive">Inactive</a></li>
              </ul>
            </div>
          </div>
          <div class="d-flex gap-2">
            <button class="btn btn-primary" data-action="add">
              <i data-lucide="plus"></i> Add New
            </button>
            <button class="btn btn-outline-secondary" data-action="export">
              <i data-lucide="download"></i> Export
            </button>
          </div>
        </div>

        <!-- Data Table -->
        <div class="card">
          <div class="table-responsive">
            <table class="table table-hover mb-0">
              <thead class="table-light">
                <tr>
                  <th><input type="checkbox" class="form-check-input" data-action="select-all"></th>
                  #{headers}
                  <th class="text-end">Actions</th>
                </tr>
              </thead>
              <tbody data-target="rows">
                <tr>
                  <td colspan="#{fields.length + 2}" class="text-center py-4">
                    <div class="spinner-border spinner-border-sm" role="status">
                      <span class="visually-hidden">Loading...</span>
                    </div>
                    Loading data...
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Pagination -->
        <div class="d-flex justify-content-between align-items-center mt-3">
          <div class="text-muted">
            Showing <span data-target="showing">0</span> of <span data-target="total">0</span> items
          </div>
          <nav>
            <ul class="pagination mb-0" data-target="pagination">
              <li class="page-item disabled"><a class="page-link" href="#">Previous</a></li>
              <li class="page-item active"><a class="page-link" href="#">1</a></li>
              <li class="page-item disabled"><a class="page-link" href="#">Next</a></li>
            </ul>
          </nav>
        </div>
      </div>
    HTML
  end

  def generate_form_html(canvas_name, model_name, fields, app_module)
    # Generate form fields
    form_fields = fields.map do |field|
      field = field.transform_keys(&:to_sym) if field.is_a?(Hash)
      field_name = field[:name] || field.to_s
      field_type = field[:type] || 'string'
      field_label = field_name.to_s.titleize
      
      generate_form_field(field_name, field_type, field_label, field)
    end.join("\n")

    <<~HTML
      <div class="module-form" data-module="#{app_module.slug}" data-controller="module-form">
        <div class="card">
          <div class="card-header">
            <h5 class="mb-0">#{canvas_name}</h5>
          </div>
          <div class="card-body">
            <form id="module-form" data-target="form">
              #{form_fields}
              
              <div class="d-flex gap-2 mt-4">
                <button type="submit" class="btn btn-primary">
                  <i data-lucide="save"></i> Save
                </button>
                <button type="button" class="btn btn-secondary" data-action="cancel">
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    HTML
  end

  def generate_form_field(name, type, label, field_config)
    required = field_config[:required] || field_config[:null] == false
    required_attr = required ? 'required' : ''
    required_indicator = required ? '<span class="text-danger">*</span>' : ''

    case type
    when 'text'
      <<~HTML
        <div class="mb-3">
          <label class="form-label">#{label} #{required_indicator}</label>
          <textarea class="form-control" name="#{name}" rows="4" #{required_attr}></textarea>
        </div>
      HTML
    when 'integer', 'decimal'
      step = type == 'decimal' ? 'step="0.01"' : ''
      <<~HTML
        <div class="mb-3">
          <label class="form-label">#{label} #{required_indicator}</label>
          <input type="number" class="form-control" name="#{name}" #{step} #{required_attr}>
        </div>
      HTML
    when 'boolean'
      <<~HTML
        <div class="mb-3 form-check">
          <input type="checkbox" class="form-check-input" name="#{name}" id="field_#{name}">
          <label class="form-check-label" for="field_#{name}">#{label}</label>
        </div>
      HTML
    when 'date'
      <<~HTML
        <div class="mb-3">
          <label class="form-label">#{label} #{required_indicator}</label>
          <input type="date" class="form-control" name="#{name}" #{required_attr}>
        </div>
      HTML
    when 'datetime'
      <<~HTML
        <div class="mb-3">
          <label class="form-label">#{label} #{required_indicator}</label>
          <input type="datetime-local" class="form-control" name="#{name}" #{required_attr}>
        </div>
      HTML
    else
      <<~HTML
        <div class="mb-3">
          <label class="form-label">#{label} #{required_indicator}</label>
          <input type="text" class="form-control" name="#{name}" #{required_attr}>
        </div>
      HTML
    end
  end

  def generate_report_html(canvas_name, model_name, app_module)
    <<~HTML
      <div class="module-report" data-module="#{app_module.slug}" data-controller="module-report">
        <div class="report-header d-flex justify-content-between align-items-center mb-4">
          <h2>#{canvas_name}</h2>
          <div class="d-flex gap-2">
            <button class="btn btn-outline-secondary" data-action="print">
              <i data-lucide="printer"></i> Print
            </button>
            <button class="btn btn-primary" data-action="export-pdf">
              <i data-lucide="file-text"></i> Export PDF
            </button>
          </div>
        </div>
        
        <div class="card">
          <div class="card-body">
            <div class="report-content" data-target="content">
              <p class="text-muted">Loading report...</p>
            </div>
          </div>
        </div>
      </div>
    HTML
  end

  def generate_js(canvas_type, canvas_slug, model_name, app_module)
    <<~JS
      // Generated Stimulus controller for #{canvas_slug}
      // Module: #{app_module.name}
      
      import { Controller } from "@hotwired/stimulus"
      
      export default class extends Controller {
        static targets = ["rows", "search", "pagination", "total", "showing", "form", "content"]
        
        connect() {
          console.log("Module canvas connected: #{canvas_slug}")
          this.loadData()
        }
        
        async loadData() {
          try {
            // TODO: Implement data loading from module API
            console.log("Loading data for #{model_name || 'module'}")
          } catch (error) {
            console.error("Failed to load data:", error)
          }
        }
        
        search(event) {
          const query = event.target.value
          console.log("Searching:", query)
          // TODO: Implement search
        }
        
        add() {
          console.log("Add new item")
          // TODO: Implement add action
        }
        
        edit(event) {
          const id = event.target.dataset.id
          console.log("Edit item:", id)
          // TODO: Implement edit action
        }
        
        delete(event) {
          const id = event.target.dataset.id
          if (confirm("Are you sure you want to delete this item?")) {
            console.log("Delete item:", id)
            // TODO: Implement delete action
          }
        }
      }
    JS
  end

  def generate_css(canvas_type, canvas_slug)
    <<~CSS
      /* Generated styles for #{canvas_slug} */
      
      .module-#{canvas_type} {
        padding: 1rem;
      }
      
      .stats-card .stats-icon {
        width: 48px;
        height: 48px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      
      .stats-card .stats-icon svg {
        width: 24px;
        height: 24px;
      }
      
      .activity-list .activity-item {
        padding: 0.75rem 0;
        border-bottom: 1px solid var(--bs-border-color);
      }
      
      .activity-list .activity-item:last-child {
        border-bottom: none;
      }
    CSS
  end

  def build_data_sources(model_name)
    return [] if model_name.blank?
    
    [
      { 
        type: 'model', 
        model: model_name, 
        scope: 'all', 
        limit: 100 
      }
    ]
  end

  def normalize_actions(actions)
    actions.map do |action|
      action = action.transform_keys(&:to_sym) if action.is_a?(Hash)
      {
        name: action[:name] || 'Action',
        icon: action[:icon] || 'circle',
        action: action[:action] || action[:name]&.parameterize || 'action'
      }
    end
  end
end


