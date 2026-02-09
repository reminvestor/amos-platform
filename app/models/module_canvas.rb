# frozen_string_literal: true

# == Schema Information
#
# Table name: module_canvases
#
#  id              :bigint           not null, primary key
#  app_module_id   :bigint           not null
#  entity_id       :bigint           not null
#  slug            :string           not null
#  name            :string           not null
#  description     :text
#  canvas_type     :string           default("module")
#  ui_mode         :string           default("simple")
#  html_content    :text
#  js_content      :text
#  css_content     :text
#  data_sources    :jsonb            default([])
#  actions         :jsonb            default([])
#  layout_config   :jsonb            default({})
#  version         :integer          default(1)
#  previous_versions :text
#  is_default      :boolean          default(false)
#  metadata        :jsonb            default({})
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
class ModuleCanvas < ApplicationRecord
  self.table_name = 'module_canvases'
  
  # Associations
  belongs_to :app_module
  belongs_to :entity

  # Canvas types
  CANVAS_TYPES = %w[module dashboard data_grid form detail kanban calendar report wizard custom].freeze
  UI_MODES = %w[simple advanced].freeze

  # Validations
  validates :slug, presence: true, uniqueness: { scope: :app_module_id }
  validates :name, presence: true
  validates :canvas_type, inclusion: { in: CANVAS_TYPES }
  validates :ui_mode, inclusion: { in: UI_MODES }
  validates :public_slug, uniqueness: true, allow_nil: true,
            format: { with: /\A[a-z0-9\-]+\z/, message: 'only lowercase letters, numbers, and hyphens', allow_nil: true }

  # Scopes
  scope :simple, -> { where(ui_mode: 'simple') }
  scope :advanced, -> { where(ui_mode: 'advanced') }
  scope :by_type, ->(type) { where(canvas_type: type) }
  scope :defaults, -> { where(is_default: true) }
  scope :ordered, -> { order(:name) }
  scope :published, -> { where(is_public: true) }
  scope :custom, -> { where(canvas_type: 'custom') }

  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? && name.present? }
  before_validation :generate_public_slug, if: -> { is_public && public_slug.blank? }
  before_update :save_previous_version, if: :html_content_changed?
  
  # ============================================
  # PUBLISHING
  # ============================================
  
  def publish!
    generate_public_slug if public_slug.blank?
    update!(is_public: true, published_at: Time.current)
  end
  
  def unpublish!
    update!(is_public: false)
  end
  
  def published?
    is_public
  end
  
  def public_url
    return nil unless is_public && public_slug.present?
    "/c/#{public_slug}"
  end
  
  def increment_view!
    increment!(:view_count)
  end

  # ============================================
  # RENDERING
  # ============================================

  # Render the canvas HTML with data context
  def render_html(data_context = {})
    template = html_content || default_html_template
    
    # Simple variable interpolation for now
    # In production, use a proper templating engine
    rendered = template.dup
    
    data_context.each do |key, value|
      rendered.gsub!("{{#{key}}}", value.to_s)
      rendered.gsub!("{{ #{key} }}", value.to_s)
    end
    
    rendered
  end

  # Get the full canvas response for Scout
  def to_canvas_response(data_context = {})
    {
      type: full_canvas_type,
      title: name,
      content: render_html(data_context),
      js_content: js_content,
      css_content: css_content,
      data: {
        module_slug: app_module.slug,
        canvas_slug: slug,
        ui_mode: ui_mode,
        actions: actions,
        data_sources: data_sources
      }
    }
  end

  def full_canvas_type
    "module_#{app_module.slug}_#{slug}"
  end

  # ============================================
  # DATA SOURCE HELPERS
  # ============================================

  def model_data_sources
    data_sources.select { |ds| ds['type'] == 'model' }
  end

  def tool_data_sources
    data_sources.select { |ds| ds['type'] == 'tool' }
  end

  def api_data_sources
    data_sources.select { |ds| ds['type'] == 'api' }
  end

  # ============================================
  # VERSIONING
  # ============================================

  def save_version!
    save_previous_version
    increment!(:version)
  end

  def restore_version!(version_number)
    versions = parsed_previous_versions
    target = versions.find { |v| v['version'] == version_number }
    
    return false unless target

    self.html_content = target['html_content']
    self.js_content = target['js_content']
    self.css_content = target['css_content']
    save!
  end

  def parsed_previous_versions
    return [] if previous_versions.blank?
    JSON.parse(previous_versions)
  rescue JSON::ParserError
    []
  end

  # ============================================
  # TEMPLATES
  # ============================================

  def default_html_template
    case canvas_type
    when 'dashboard'
      dashboard_template
    when 'data_grid'
      data_grid_template
    when 'form'
      form_template
    else
      module_template
    end
  end

  private

  def generate_slug
    base_slug = name.parameterize.underscore
    self.slug = base_slug
    
    counter = 1
    while ModuleCanvas.where(app_module: app_module, slug: slug).exists?
      self.slug = "#{base_slug}_#{counter}"
      counter += 1
    end
  end
  
  def generate_public_slug
    base_slug = name.parameterize.downcase
    self.public_slug = base_slug
    
    counter = 1
    while ModuleCanvas.where(public_slug: public_slug).where.not(id: id).exists?
      self.public_slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def save_previous_version
    return if html_content_was.blank?
    
    versions = parsed_previous_versions
    versions << {
      version: version,
      html_content: html_content_was,
      js_content: js_content_was,
      css_content: css_content_was,
      saved_at: Time.current.iso8601
    }
    
    # Keep last 10 versions
    versions = versions.last(10)
    self.previous_versions = versions.to_json
  end

  def dashboard_template
    <<~HTML
      <div class="module-dashboard" data-module="{{module_slug}}">
        <div class="dashboard-header">
          <h2>{{title}}</h2>
        </div>
        <div class="dashboard-content">
          <div class="row">
            <!-- Dashboard cards will be rendered here -->
            {{content}}
          </div>
        </div>
      </div>
    HTML
  end

  def data_grid_template
    <<~HTML
      <div class="module-data-grid" data-module="{{module_slug}}">
        <div class="grid-toolbar">
          <div class="grid-search">
            <input type="text" placeholder="Search..." class="form-control">
          </div>
          <div class="grid-actions">
            {{actions}}
          </div>
        </div>
        <div class="grid-container">
          <table class="table table-hover">
            <thead>
              {{table_headers}}
            </thead>
            <tbody>
              {{table_rows}}
            </tbody>
          </table>
        </div>
        <div class="grid-pagination">
          {{pagination}}
        </div>
      </div>
    HTML
  end

  def form_template
    <<~HTML
      <div class="module-form" data-module="{{module_slug}}">
        <form id="module-form-{{slug}}">
          <div class="form-content">
            {{form_fields}}
          </div>
          <div class="form-actions">
            <button type="submit" class="btn btn-primary">Save</button>
            <button type="button" class="btn btn-secondary" data-action="cancel">Cancel</button>
          </div>
        </form>
      </div>
    HTML
  end

  def module_template
    <<~HTML
      <div class="module-canvas" data-module="{{module_slug}}" data-canvas="{{slug}}">
        <div class="module-header">
          <h2>{{title}}</h2>
          <div class="module-actions">
            {{header_actions}}
          </div>
        </div>
        <div class="module-content">
          {{content}}
        </div>
      </div>
    HTML
  end
end

