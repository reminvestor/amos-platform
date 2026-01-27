# frozen_string_literal: true

# DesignPlan stores the plan/blueprint for landing pages, websites, apps, and canvases
# before they're actually built. This supports the unified "Plan → Build" workflow.
#
# Status flow:
#   draft → building → completed
#                   ↘ failed
#
# Design Types:
#   - landing_page: Single page, mostly static
#   - website: Multi-page site, mostly static
#   - app: Website + data sources = dynamic web app
#   - canvas: Internal tool/dashboard with data sources
#
class DesignPlan < ApplicationRecord
  # Associations
  belongs_to :entity
  belongs_to :user
  belongs_to :landing_page, optional: true
  belongs_to :website, optional: true
  belongs_to :app, optional: true
  belongs_to :module_canvas, optional: true

  # Design types
  DESIGN_TYPES = %w[landing_page website app canvas portfolio single_page].freeze
  STATUSES = %w[draft building completed failed].freeze

  # Validations
  validates :name, presence: true
  validates :design_type, presence: true, inclusion: { in: DESIGN_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Scopes
  scope :drafts, -> { where(status: 'draft') }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_landing_pages, -> { where(design_type: 'landing_page') }
  scope :for_websites, -> { where(design_type: 'website') }
  scope :for_apps, -> { where(design_type: 'app') }
  scope :for_canvases, -> { where(design_type: 'canvas') }
  scope :with_data_sources, -> { where("jsonb_array_length(data_sources) > 0") }

  # ============================================
  # TYPE HELPERS
  # ============================================

  def landing_page?
    design_type == 'landing_page'
  end

  def website?
    design_type == 'website'
  end

  def app?
    design_type == 'app'
  end

  def canvas?
    design_type == 'canvas'
  end

  # An app or canvas has dynamic data binding
  def dynamic?
    app? || canvas?
  end

  # Has external deployment (vs internal only)
  def external?
    landing_page? || website? || app?
  end

  # ============================================
  # PLAN DATA ACCESSORS
  # ============================================

  # Get page names for multi-page plans
  def page_names
    plan_data.dig('pages')&.map { |p| p['name'] } || []
  end

  # Get page count
  def page_count
    plan_data['pages']&.length || 1
  end

  # Get section names (for single-page or flattened)
  def section_names
    plan_data.dig('sections')&.map { |s| s['name'] } || []
  end

  # Get color scheme
  def color_scheme
    plan_data['color_scheme'] || {}
  end

  # Get style
  def style
    plan_data['style'] || 'Modern'
  end

  # ============================================
  # DATA SOURCE MANAGEMENT
  # ============================================

  # Data source structure:
  # {
  #   "name": "revenue_data",
  #   "type": "workflow" | "integration" | "model",
  #   "source_id": 123,  # workflow_id, integration_action_id, or app_module_id
  #   "output_path": "data.results",  # JSONPath to the data within the output
  #   "refresh_interval": 300,  # seconds, 0 = manual only
  #   "transform": null  # optional JS/Ruby transform
  # }

  def add_data_source!(source_config)
    sources = data_sources || []
    sources << source_config.with_indifferent_access
    update!(data_sources: sources)
  end

  def remove_data_source!(name)
    sources = data_sources || []
    sources.reject! { |ds| ds['name'] == name }
    update!(data_sources: sources)
  end

  def update_data_source!(name, updates)
    sources = data_sources || []
    source = sources.find { |ds| ds['name'] == name }
    return false unless source

    source.merge!(updates.with_indifferent_access)
    update!(data_sources: sources)
  end

  def find_data_source(name)
    (data_sources || []).find { |ds| ds['name'] == name }
  end

  def data_source_names
    (data_sources || []).map { |ds| ds['name'] }
  end

  def workflow_data_sources
    (data_sources || []).select { |ds| ds['type'] == 'workflow' }
  end

  def integration_data_sources
    (data_sources || []).select { |ds| ds['type'] == 'integration' }
  end

  def model_data_sources
    (data_sources || []).select { |ds| ds['type'] == 'model' }
  end

  # ============================================
  # SUMMARY & DISPLAY
  # ============================================

  def summary
    sections = plan_data['sections'] || []
    {
      design_type: design_type,
      section_count: sections.count,
      sections: section_names,
      page_count: page_count,
      style: style,
      primary_color: color_scheme['primary'],
      data_source_count: (data_sources || []).count,
      layout: plan_data['layout'] || 'single-column'
    }
  end

  def to_preview
    {
      id: id,
      name: name,
      design_type: design_type,
      description: description,
      status: status,
      summary: summary,
      data_sources: data_sources,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end
end
