# frozen_string_literal: true

# WebsiteBuilderService creates and configures Websites, WebsitePages, and WebApps
# from plan specifications.
#
# Usage:
#   service = WebsiteBuilderService.new(entity: entity, user: user)
#   website = service.create_website(spec)
#   web_app = service.create_web_app(spec, website: website, modules: [app_module])
#
class WebsiteBuilderService
  attr_reader :entity, :user
  
  def initialize(entity:, user:)
    @entity = entity
    @user = user
  end
  
  # ============================================
  # WEBSITE CREATION
  # ============================================
  
  # Create a website from a spec
  # spec: { name, slug, theme, features, pages: [...] }
  def create_website(spec, application_plan: nil)
    spec = spec.with_indifferent_access
    
    website = Website.create!(
      entity: entity,
      created_by: user,
      application_plan: application_plan,
      name: spec[:name],
      slug: spec[:slug] || spec[:name].parameterize,
      description: spec[:description],
      theme: spec[:theme] || 'modern',
      theme_config: build_theme_config(spec),
      features: spec[:features] || [],
      status: 'draft'
    )
    
    # Create pages
    pages_spec = spec[:pages] || default_pages(spec[:name])
    pages_spec.each_with_index do |page_spec, index|
      create_website_page(website, page_spec, nav_order: index)
    end
    
    # Generate default layout if not provided
    website.update!(
      header_html: spec[:header_html] || generate_header(website),
      footer_html: spec[:footer_html] || generate_footer(website)
    )
    
    website
  end
  
  # Create a page within a website
  def create_website_page(website, spec, nav_order: 0)
    spec = spec.with_indifferent_access
    
    # Find associated module if this is a dynamic page
    app_module = nil
    if spec[:module_slug].present?
      app_module = AppModule.find_by(slug: spec[:module_slug], entity_id: entity.id)
    end
    
    page = WebsitePage.create!(
      website: website,
      entity: entity,
      name: spec[:name],
      slug: spec[:slug] || spec[:name].parameterize,
      description: spec[:description],
      template: spec[:template] || 'content',
      is_homepage: spec[:is_homepage] || false,
      is_dynamic: spec[:is_dynamic] || app_module.present?,
      app_module: app_module,
      module_view_type: spec[:module_view_type],
      module_config: spec[:module_config] || {},
      show_in_nav: spec[:show_in_nav] != false,
      nav_order: nav_order,
      nav_label: spec[:nav_label],
      requires_auth: spec[:requires_auth] || false,
      status: 'draft'
    )
    
    # Generate template HTML — use Liquid templates for dynamic pages
    html = spec[:html_content]
    html ||= generate_liquid_template(page, app_module, spec) if app_module.present?
    html ||= page.generate_template_html
    
    page.update!(html_content: html)
    
    page
  end
  
  # Generate a Liquid template for dynamic pages bound to modules
  def generate_liquid_template(page, app_module, spec)
    fields = app_module.metadata&.dig('schema', 'fields') || []
    # If no schema fields, try to get from module spec
    if fields.empty?
      # Walk the plan spec for this module's fields
      plan = page.website&.application_plan
      if plan
        mod_spec = plan.plan_spec&.dig('modules')&.find { |m| m['slug'] == app_module.slug }
        fields = mod_spec&.dig('fields') || []
      end
    end
    
    generator = WebsiteTemplateGenerator.new
    generator.generate(
      page_type: spec[:template] || page.template,
      module_name: app_module.name,
      module_slug: app_module.slug,
      fields: fields,
      options: spec.slice(:theme, :features)
    )
  rescue => e
    Rails.logger.warn "[WebsiteBuilderService] Liquid template generation failed: #{e.message}"
    nil
  end
  
  # ============================================
  # WEB APP CREATION
  # ============================================
  
  # Create a web app from a spec
  # spec: { name, auth_config, roles, features }
  def create_web_app(spec, website: nil, modules: [], application_plan: nil)
    spec = spec.with_indifferent_access
    
    web_app = WebApp.create!(
      entity: entity,
      created_by: user,
      application_plan: application_plan,
      website: website,
      name: spec[:name],
      slug: spec[:slug] || spec[:name].parameterize,
      description: spec[:description],
      requires_auth: spec[:requires_auth] != false,
      auth_config: build_auth_config(spec),
      roles: spec[:roles] || default_roles,
      features: spec[:features] || default_features,
      primary_color: spec[:primary_color],
      logo_url: spec[:logo_url],
      branding: spec[:branding] || {},
      status: 'draft'
    )
    
    # Link modules
    modules.each do |app_module|
      module_config = spec.dig(:modules, app_module.slug.to_sym) || {}
      
      web_app.web_app_modules.create!(
        app_module: app_module,
        is_public: module_config[:is_public] || false,
        allow_create: module_config[:allow_create] || true,
        allow_edit: module_config[:allow_edit] || true,
        allow_delete: module_config[:allow_delete] || false,
        visible_fields: module_config[:visible_fields] || [],
        editable_fields: module_config[:editable_fields] || []
      )
    end
    
    web_app
  end
  
  # ============================================
  # CONVERSION HELPERS
  # ============================================
  
  # Convert a LandingPage to a Website
  def convert_landing_page_to_website(landing_page)
    website = Website.create!(
      entity: entity,
      created_by: user,
      name: landing_page.title,
      slug: landing_page.slug,
      description: landing_page.meta_description,
      theme: 'modern',
      status: 'draft'
    )
    
    # Create homepage from landing page content
    WebsitePage.create!(
      website: website,
      entity: entity,
      name: 'Home',
      slug: 'index',
      is_homepage: true,
      template: 'landing',
      html_content: landing_page.html_content,
      status: 'published'
    )
    
    website
  end
  
  # Convert a Website to a WebApp
  def convert_website_to_web_app(website, modules: [], auth_config: {})
    web_app = WebApp.create!(
      entity: entity,
      created_by: user,
      website: website,
      name: website.name,
      slug: "#{website.slug}-app",
      description: website.description,
      requires_auth: true,
      auth_config: build_auth_config(auth_config),
      roles: default_roles,
      features: default_features,
      status: 'draft'
    )
    
    # Link modules with default permissions
    modules.each do |app_module|
      web_app.add_module!(app_module, {
        is_public: false,
        allow_create: true,
        allow_edit: true,
        allow_delete: false
      })
    end
    
    # Update website pages that require auth
    website.website_pages.where(requires_auth: true).find_each do |page|
      page.update!(requires_auth: true)
    end
    
    web_app
  end
  
  private
  
  # ============================================
  # DEFAULTS & BUILDERS
  # ============================================
  
  def default_pages(name)
    [
      { name: 'Home', slug: 'index', template: 'homepage', is_homepage: true },
      { name: 'About', slug: 'about', template: 'content' },
      { name: 'Contact', slug: 'contact', template: 'form' }
    ]
  end
  
  def default_roles
    [
      { 'name' => 'admin', 'permissions' => ['*'] },
      { 'name' => 'editor', 'permissions' => ['read', 'create', 'edit'] },
      { 'name' => 'user', 'permissions' => ['read', 'create'] },
      { 'name' => 'guest', 'permissions' => ['read'] }
    ]
  end
  
  def default_features
    %w[user_dashboard notifications search]
  end
  
  def build_theme_config(spec)
    {
      'primary_color' => spec[:primary_color] || '#0d6efd',
      'secondary_color' => spec[:secondary_color] || '#6c757d',
      'font_family' => spec[:font_family] || 'Inter, system-ui, sans-serif',
      'header_style' => spec[:header_style] || 'sticky',
      'footer_style' => spec[:footer_style] || 'minimal'
    }
  end
  
  def build_auth_config(spec)
    {
      'methods' => spec[:auth_methods] || ['email'],
      'allow_registration' => spec[:allow_registration] != false,
      'require_email_verification' => spec[:require_email_verification] || false,
      'session_timeout' => spec[:session_timeout] || 3600
    }
  end
  
  def generate_header(website)
    nav_items = website.nav_pages.map do |page|
      "<li class=\"nav-item\"><a class=\"nav-link\" href=\"/#{page.slug}\">#{page.nav_text}</a></li>"
    end.join("\n")
    
    <<~HTML
      <nav class="navbar navbar-expand-lg navbar-light bg-white border-bottom sticky-top">
        <div class="container">
          <a class="navbar-brand fw-bold" href="/" style="color: var(--primary-color);">#{website.name}</a>
          <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav">
            <span class="navbar-toggler-icon"></span>
          </button>
          <div class="collapse navbar-collapse" id="navbarNav">
            <ul class="navbar-nav ms-auto">
              #{nav_items}
            </ul>
          </div>
        </div>
      </nav>
    HTML
  end
  
  def generate_footer(website)
    <<~HTML
      <footer class="bg-light py-4 mt-5 border-top">
        <div class="container">
          <div class="row">
            <div class="col-md-6">
              <p class="mb-0 text-muted">&copy; #{Time.current.year} #{website.name}</p>
            </div>
            <div class="col-md-6 text-md-end">
              <a href="/privacy" class="text-muted me-3">Privacy Policy</a>
              <a href="/terms" class="text-muted">Terms of Service</a>
            </div>
          </div>
        </div>
      </footer>
    HTML
  end
end

