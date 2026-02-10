# frozen_string_literal: true

# Website represents a multi-page website with shared layout
#
# Progression: LandingPage (single page) → Website (multi-page) → WebApp (website + modules)
#
class Website < ApplicationRecord
  # Associations
  belongs_to :entity
  belongs_to :created_by, class_name: 'User'
  belongs_to :application_plan, optional: true
  belongs_to :custom_domain, optional: true
  
  has_many :website_pages, dependent: :destroy
  has_one :web_app, dependent: :nullify
  
  # Statuses
  STATUSES = %w[draft published archived].freeze
  THEMES = %w[modern minimal corporate creative tech elegant].freeze
  
  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :entity_id }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :theme, inclusion: { in: THEMES }, allow_nil: true
  validates :subdomain, uniqueness: true, allow_nil: true, 
            format: { with: /\A[a-z0-9-]+\z/, message: 'only lowercase letters, numbers, and hyphens' }
  validates :custom_domain, uniqueness: true, allow_nil: true
  
  # Scopes
  scope :published, -> { where(status: 'published') }
  scope :draft, -> { where(status: 'draft') }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  
  # Callbacks
  before_validation :generate_slug, on: :create
  before_create :generate_default_layout
  
  # ============================================
  # STATUS HELPERS
  # ============================================
  
  def published?
    status == 'published'
  end
  
  def draft?
    status == 'draft'
  end
  
  def publish!
    update!(status: 'published', published_at: Time.current)
  end
  
  def unpublish!
    update!(status: 'draft')
  end
  
  def archive!
    update!(status: 'archived')
  end
  
  # ============================================
  # PAGE HELPERS
  # ============================================
  
  def homepage
    website_pages.find_by(is_homepage: true) || website_pages.order(:nav_order).first
  end
  
  def nav_pages
    website_pages.where(show_in_nav: true).order(:nav_order)
  end
  
  def page_count
    website_pages.count
  end
  
  def add_page!(name:, template: 'content', is_homepage: false)
    website_pages.create!(
      entity: entity,
      name: name,
      slug: name.parameterize,
      template: template,
      is_homepage: is_homepage,
      nav_order: website_pages.count
    )
  end
  
  # ============================================
  # URL HELPERS
  # ============================================
  
  def public_url
    if custom_domain.present?
      "https://#{custom_domain}"
    elsif subdomain.present?
      "https://#{subdomain}.amoslabs.com"
    else
      "/sites/#{slug}"
    end
  end
  
  def preview_url
    "/sites/#{slug}/preview"
  end
  
  # ============================================
  # RENDERING
  # ============================================
  
  def render_page(page, data: {}, rendered_content: nil)
    content = rendered_content || page.html_content
    layout = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{page.meta_title || page.name} - #{name}</title>
        <meta name="description" content="#{page.meta_description || meta_description}">
        #{favicon_tag}
        #{theme_styles}
        #{custom_css.present? ? "<style>#{custom_css}</style>" : ''}
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
      </head>
      <body>
        #{header_html || default_header}
        <main>
          #{content}
        </main>
        #{footer_html || default_footer}
        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
        #{custom_js.present? ? "<script>#{custom_js}</script>" : ''}
        #{analytics_script}
      </body>
      </html>
    HTML
    
    layout
  end
  
  def theme_styles
    config = theme_config.with_indifferent_access
    primary = config[:primary_color] || '#0d6efd'
    secondary = config[:secondary_color] || '#6c757d'
    font = config[:font_family] || 'Inter, system-ui, sans-serif'
    
    <<~CSS
      <style>
        :root {
          --primary-color: #{primary};
          --secondary-color: #{secondary};
          --font-family: #{font};
        }
        body { font-family: var(--font-family); }
        .btn-primary { background: var(--primary-color); border-color: var(--primary-color); }
        a { color: var(--primary-color); }
      </style>
    CSS
  end
  
  def to_preview
    {
      id: id,
      name: name,
      slug: slug,
      status: status,
      theme: theme,
      page_count: page_count,
      public_url: public_url,
      published_at: published_at&.iso8601
    }
  end
  
  private
  
  def generate_slug
    self.slug ||= name&.parameterize
  end
  
  def generate_default_layout
    self.header_html ||= default_header
    self.footer_html ||= default_footer
  end
  
  def default_header
    <<~HTML
      <nav class="navbar navbar-expand-lg navbar-light bg-white border-bottom">
        <div class="container">
          <a class="navbar-brand fw-bold" href="/">#{name}</a>
          <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav">
            <span class="navbar-toggler-icon"></span>
          </button>
          <div class="collapse navbar-collapse" id="navbarNav">
            <ul class="navbar-nav ms-auto">
              <!-- Nav items will be rendered dynamically -->
            </ul>
          </div>
        </div>
      </nav>
    HTML
  end
  
  def default_footer
    <<~HTML
      <footer class="bg-light py-4 mt-5">
        <div class="container text-center">
          <p class="mb-0 text-muted">&copy; #{Time.current.year} #{name}. Powered by AMOS.</p>
        </div>
      </footer>
    HTML
  end
  
  def favicon_tag
    return '' unless favicon_url.present?
    "<link rel=\"icon\" href=\"#{favicon_url}\">"
  end
  
  def analytics_script
    return '' unless google_analytics_id.present?
    <<~HTML
      <script async src="https://www.googletagmanager.com/gtag/js?id=#{google_analytics_id}"></script>
      <script>
        window.dataLayer = window.dataLayer || [];
        function gtag(){dataLayer.push(arguments);}
        gtag('js', new Date());
        gtag('config', '#{google_analytics_id}');
      </script>
    HTML
  end
end

