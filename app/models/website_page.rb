# frozen_string_literal: true

# WebsitePage represents an individual page within a Website
#
# Pages can be:
# - Static content pages (about, contact)
# - Dynamic pages showing module data (blog list, article detail)
# - Form pages for data collection
#
class WebsitePage < ApplicationRecord
  # Associations
  belongs_to :website
  belongs_to :entity
  belongs_to :app_module, optional: true  # For dynamic content
  
  # Templates
  TEMPLATES = %w[homepage content list detail form landing custom].freeze
  STATUSES = %w[draft published archived].freeze
  
  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :website_id }
  validates :template, inclusion: { in: TEMPLATES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  
  # Scopes
  scope :published, -> { where(status: 'published') }
  scope :in_nav, -> { where(show_in_nav: true).order(:nav_order) }
  scope :dynamic, -> { where(is_dynamic: true) }
  scope :static, -> { where(is_dynamic: false) }
  
  # Callbacks
  before_validation :set_defaults, on: :create
  after_save :update_homepage_flag, if: :saved_change_to_is_homepage?
  
  # ============================================
  # STATUS
  # ============================================
  
  def published?
    status == 'published'
  end
  
  def publish!
    update!(status: 'published', published_at: Time.current)
  end
  
  def unpublish!
    update!(status: 'draft')
  end
  
  # ============================================
  # URL & NAVIGATION
  # ============================================
  
  def url
    if is_homepage?
      website.public_url
    else
      "#{website.public_url}/#{slug}"
    end
  end
  
  def nav_text
    nav_label.presence || name
  end
  
  # ============================================
  # CONTENT
  # ============================================
  
  def render(data: {}, params: {})
    # Render content through Liquid if this page has module data binding
    rendered_content = if liquid_template?
      render_liquid(params: params)
    else
      html_content
    end

    if use_website_layout?
      website.render_page(self, data: data, rendered_content: rendered_content)
    else
      standalone_render(data: data, rendered_content: rendered_content)
    end
  end
  
  def standalone_render(data: {}, rendered_content: nil)
    content = rendered_content || html_content
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{meta_title || name}</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
      </head>
      <body>
        #{custom_header_html}
        <main>#{content}</main>
        #{custom_footer_html}
        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
      </body>
      </html>
    HTML
  end
  
  # Check if this page uses Liquid templates (contains Liquid tags or variables)
  def liquid_template?
    return false if html_content.blank?
    html_content.include?('{{') || html_content.include?('{%')
  end
  
  # Render the page content through the Liquid template engine
  def render_liquid(params: {})
    renderer = Modules::LiquidTemplateRenderer.new(entity: entity)
    renderer.render_page(self, params: params)
  end
  
  # ============================================
  # DYNAMIC CONTENT (Module Integration)
  # ============================================
  
  def dynamic?
    is_dynamic && app_module.present?
  end
  
  def fetch_module_data(params = {})
    return [] unless dynamic?
    
    model_class = app_module.dynamic_model_class
    return [] unless model_class
    
    records = model_class.where(entity_id: entity_id)
    
    # Apply filters from module_config
    config = module_config.with_indifferent_access
    if config[:filters].present?
      config[:filters].each do |field, value|
        records = records.where(field => value)
      end
    end
    
    # Apply limit
    records = records.limit(config[:limit] || 50)
    
    # Apply ordering
    if config[:order_by].present?
      direction = config[:order_direction] || 'desc'
      records = records.order(config[:order_by] => direction)
    end
    
    records.to_a
  end
  
  def fetch_single_record(id_or_slug)
    return nil unless dynamic?
    
    model_class = app_module.dynamic_model_class
    return nil unless model_class
    
    # Try by ID first, then by slug if available
    record = model_class.find_by(id: id_or_slug, entity_id: entity_id)
    record ||= model_class.find_by(slug: id_or_slug, entity_id: entity_id) if model_class.column_names.include?('slug')
    record
  end
  
  # ============================================
  # CONTENT BLOCKS
  # ============================================
  
  def add_content_block(type:, data: {}, position: nil)
    blocks = content_blocks.dup
    block = { type: type, data: data, id: SecureRandom.uuid }
    
    if position.present?
      blocks.insert(position, block)
    else
      blocks << block
    end
    
    update!(content_blocks: blocks)
    block
  end
  
  def update_content_block(block_id, data)
    blocks = content_blocks.map do |block|
      if block['id'] == block_id
        block.merge('data' => data)
      else
        block
      end
    end
    update!(content_blocks: blocks)
  end
  
  def remove_content_block(block_id)
    blocks = content_blocks.reject { |b| b['id'] == block_id }
    update!(content_blocks: blocks)
  end
  
  def render_content_blocks
    content_blocks.map { |block| render_block(block) }.join("\n")
  end
  
  # ============================================
  # TEMPLATE-SPECIFIC RENDERING
  # ============================================
  
  def generate_template_html
    case template
    when 'homepage'
      generate_homepage_html
    when 'list'
      generate_list_html
    when 'detail'
      generate_detail_html
    when 'form'
      generate_form_html
    when 'landing'
      generate_landing_html
    else
      html_content || '<div class="container py-5"><p>Add content here</p></div>'
    end
  end
  
  private
  
  def set_defaults
    self.entity ||= website&.entity
    self.slug ||= name&.parameterize
    self.status ||= 'draft'
    self.template ||= 'content'
    self.nav_order ||= website&.website_pages&.count || 0
  end
  
  def update_homepage_flag
    return unless is_homepage?
    
    # Ensure only one homepage
    website.website_pages.where.not(id: id).update_all(is_homepage: false)
  end
  
  def render_block(block)
    type = block['type']
    data = block['data'] || {}
    
    case type
    when 'hero'
      <<~HTML
        <section class="hero bg-primary text-white py-5">
          <div class="container text-center">
            <h1 class="display-4">#{data['title']}</h1>
            <p class="lead">#{data['subtitle']}</p>
            #{data['cta_text'].present? ? "<a href='#{data['cta_link']}' class='btn btn-light btn-lg'>#{data['cta_text']}</a>" : ''}
          </div>
        </section>
      HTML
    when 'features'
      features_html = (data['features'] || []).map do |f|
        "<div class='col-md-4'><h4>#{f['title']}</h4><p>#{f['description']}</p></div>"
      end.join
      <<~HTML
        <section class="features py-5">
          <div class="container">
            <h2 class="text-center mb-4">#{data['title']}</h2>
            <div class="row">#{features_html}</div>
          </div>
        </section>
      HTML
    when 'text'
      "<section class='py-4'><div class='container'>#{data['content']}</div></section>"
    when 'image'
      "<section class='py-4'><div class='container text-center'><img src='#{data['src']}' alt='#{data['alt']}' class='img-fluid'></div></section>"
    when 'cta'
      <<~HTML
        <section class="cta bg-light py-5">
          <div class="container text-center">
            <h2>#{data['title']}</h2>
            <p>#{data['description']}</p>
            <a href="#{data['button_link']}" class="btn btn-primary btn-lg">#{data['button_text']}</a>
          </div>
        </section>
      HTML
    when 'module_canvas'
      # Embed a published module canvas into a website page
      canvas = ModuleCanvas.find_by(id: data['canvas_id'])
      if canvas
        output = ""
        output += "<style>#{canvas.css_content}</style>\n" if canvas.css_content.present?
        output += canvas.render_html(data)
        output += "\n<script>#{canvas.js_content}</script>" if canvas.js_content.present?
        "<section class='py-4'><div class='container'>#{output}</div></section>"
      else
        "<div class='content-block text-muted text-center py-3'>Canvas not found</div>"
      end
    when 'module_data'
      # Render module data using a Liquid template inline
      template = data['template'] || ''
      if template.present? && entity.present?
        app_mod = AppModule.find_by(id: data['module_id'], entity_id: entity_id)
        if app_mod
          renderer = Modules::LiquidTemplateRenderer.new(entity: entity)
          records = app_mod.dynamic_model_class&.where(entity_id: entity_id)&.limit(data['limit'] || 10)&.to_a || []
          collection_name = app_mod.slug.pluralize
          renderer.render(
            template_string: template,
            module_data: { collection_name => records.map { |r| Modules::ModuleRecordDrop.new(r) } }
          )
        else
          ''
        end
      else
        ''
      end
    else
      "<div class='content-block' data-type='#{type}'>#{data.to_json}</div>"
    end
  end
  
  def generate_homepage_html
    <<~HTML
      <section class="hero bg-primary text-white py-5">
        <div class="container text-center">
          <h1 class="display-4">#{website.name}</h1>
          <p class="lead">#{website.description || 'Welcome to our site'}</p>
        </div>
      </section>
      <section class="py-5">
        <div class="container">
          <div class="row">
            <div class="col-12 text-center">
              <p>Add content to your homepage</p>
            </div>
          </div>
        </div>
      </section>
    HTML
  end
  
  def generate_list_html
    return html_content unless dynamic?
    
    <<~HTML
      <section class="py-5">
        <div class="container">
          <h1>#{name}</h1>
          <div class="row" id="module-list" data-module="#{app_module&.slug}">
            <!-- Records loaded dynamically -->
          </div>
        </div>
      </section>
    HTML
  end
  
  def generate_detail_html
    <<~HTML
      <section class="py-5">
        <div class="container">
          <article id="module-detail" data-module="#{app_module&.slug}">
            <!-- Record loaded dynamically based on URL param -->
          </article>
        </div>
      </section>
    HTML
  end
  
  def generate_form_html
    <<~HTML
      <section class="py-5">
        <div class="container">
          <h1>#{name}</h1>
          <form id="module-form" data-module="#{app_module&.slug}">
            <!-- Form fields generated from module schema -->
            <button type="submit" class="btn btn-primary">Submit</button>
          </form>
        </div>
      </section>
    HTML
  end
  
  def generate_landing_html
    <<~HTML
      <section class="hero bg-gradient py-5">
        <div class="container text-center">
          <h1 class="display-3 fw-bold">#{name}</h1>
          <p class="lead">#{description}</p>
          <a href="#contact" class="btn btn-primary btn-lg">Get Started</a>
        </div>
      </section>
    HTML
  end
end

