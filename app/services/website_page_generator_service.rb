# frozen_string_literal: true

# WebsitePageGeneratorService
#
# Generates HTML content for website pages, with distinct modes:
# - **Marketing pages**: Hero sections, CTAs, testimonials, lead capture (like landing pages)
# - **Functional pages**: Dashboards, forms, data tables, task views, interactive UI
#
# Unlike GenerateLandingPageTool, this service:
# - Writes directly to WebsitePage.html_content (no LandingPage record created)
# - Uses different AI prompts based on page purpose
# - Respects website-level header/footer/theme for consistent layout
#
class WebsitePageGeneratorService
  FUNCTIONAL_TEMPLATES = %w[dashboard form list detail settings calendar kanban].freeze
  MARKETING_TEMPLATES = %w[homepage landing].freeze

  def initialize(user:, entity:, website: nil)
    @user = user
    @entity = entity
    @website = website
    @ai_service = BedrockService.new(user: user, entity: entity)
  end

  # Generate a single page
  #
  # @param page_data [Hash] with keys:
  #   - title: Page title
  #   - description: What the page should do/show
  #   - template: One of WebsitePage::TEMPLATES (homepage, content, list, detail, form, landing, custom)
  #   - page_purpose: "functional" or "marketing" (auto-detected if not provided)
  #   - features: Array of feature descriptions for functional pages
  #   - module_slug: Optional app module slug to connect data to
  # @return [Hash] { success: true, html_content: "...", page_type: "functional"|"marketing" }
  def generate(page_data)
    page_data = page_data.with_indifferent_access if page_data.is_a?(Hash)

    title = page_data[:title] || "Page"
    description = page_data[:description] || ""
    template = page_data[:template] || infer_template(title, description)
    page_purpose = page_data[:page_purpose] || infer_purpose(template, title, description)

    Rails.logger.info "[WebsitePageGenerator] Generating #{page_purpose} page: '#{title}' (template: #{template})"

    html_content = if page_purpose == "marketing"
      generate_marketing_page(title: title, description: description, template: template, page_data: page_data)
    else
      generate_functional_page(title: title, description: description, template: template, page_data: page_data)
    end

    {
      success: true,
      html_content: html_content,
      page_type: page_purpose,
      template: template
    }
  rescue => e
    Rails.logger.error "[WebsitePageGenerator] Generation failed: #{e.message}"
    { success: false, error: e.message }
  end

  private

  # ═══════════════════════════════════════════════════════════════
  # FUNCTIONAL PAGE GENERATION
  # ═══════════════════════════════════════════════════════════════

  def generate_functional_page(title:, description:, template:, page_data:)
    features = page_data[:features] || []
    module_slug = page_data[:module_slug]
    data_fields = page_data[:data_fields] || page_data[:fields] || []

    # Build the business context
    profile = @entity.respond_to?(:business_profile) ? (@entity.business_profile rescue nil) : nil
    business_name = profile&.dig("company_name") || @entity.name || "App"
    brand_colors = profile&.dig("brand_colors") || []
    primary_color = brand_colors.first || "#6366f1"

    prompt = <<~PROMPT
      Generate a complete, functional HTML page for a web application.

      === PAGE DETAILS ===
      Title: #{title}
      Purpose: #{description}
      Template Type: #{template}
      App Name: #{business_name}
      #{features.any? ? "Features to include:\n#{features.map { |f| "  - #{f}" }.join("\n")}" : ""}
      #{data_fields.any? ? "Data fields:\n#{data_fields.map { |f| "  - #{f}" }.join("\n")}" : ""}
      #{module_slug.present? ? "Connected module: #{module_slug}" : ""}

      === DESIGN REQUIREMENTS ===
      This is a FUNCTIONAL APPLICATION page, NOT a marketing/landing page.
      - Use Bootstrap 5 for layout and components
      - Include a clean top navigation bar with the app name and nav links
      - Use a sidebar or tab layout if appropriate for the page type
      - Professional, clean, modern SaaS-style design
      #{brand_colors.any? ? "- Brand colors: #{brand_colors.join(', ')}" : "- Primary color: #{primary_color}"}
      - Mobile-responsive
      - Light and dark mode compatible (use CSS variables)

      === TEMPLATE-SPECIFIC GUIDELINES ===
      #{template_guidelines(template)}

      === TECHNICAL REQUIREMENTS ===
      - Complete HTML document (<!DOCTYPE html> to </html>)
      - Include Bootstrap 5 CSS via CDN
      - Include Lucide icons via CDN (use <i data-lucide="icon-name"></i>)
      - Include working JavaScript for interactivity:
        - Tab switching, collapsible sections, modals
        - Form validation (if forms present)
        - Data table sorting/filtering (if tables present)
        - Drag and drop (if kanban/board present)
      - Use localStorage for data persistence (demo data)
      - All buttons and interactive elements MUST be wired up with event listeners
      - Use Font Awesome or Lucide for icons
      - NO placeholder text like "Lorem ipsum" — use realistic demo data

      === CRITICAL RULES ===
      - This is NOT a landing page. Do NOT include:
        - Hero sections with big marketing headlines
        - Testimonial sections
        - Pricing tables
        - "Sign up now" CTAs
        - Marketing copy or sales language
      - This IS an application page. DO include:
        - Functional UI elements (buttons, forms, tables, charts)
        - Navigation (sidebar or top nav)
        - Action buttons (Add, Edit, Delete, Save, etc.)
        - Status indicators, badges, progress bars
        - Empty states with helpful messages
        - Breadcrumbs or back navigation

      === TEXT READABILITY ===
      - Every piece of text must be readable against its background
      - Dark backgrounds = light/white text. Light backgrounds = dark text
      - Use proper contrast ratios

      Return ONLY the complete HTML (from <!DOCTYPE html> to </html>).
      Make it feel like a real, production-quality web application page.
      MUST include </body></html> at the end — incomplete HTML is unusable!
    PROMPT

    call_ai(prompt)
  end

  # ═══════════════════════════════════════════════════════════════
  # MARKETING PAGE GENERATION
  # ═══════════════════════════════════════════════════════════════

  def generate_marketing_page(title:, description:, template:, page_data:)
    profile = @entity.respond_to?(:business_profile) ? (@entity.business_profile rescue nil) : nil
    business_name = page_data[:business_name] || profile&.dig("company_name") || @entity.name || "Business"
    brand_colors = profile&.dig("brand_colors") || []
    cta_text = page_data[:cta_text] || "Get Started"
    value_prop = page_data[:value_proposition] || description

    prompt = <<~PROMPT
      Generate a complete marketing/content page HTML for a business website.

      === PAGE DETAILS ===
      Company: #{business_name}
      Page Title: #{title}
      Page Type: #{template} (#{template == 'homepage' ? 'main homepage' : 'content page'})
      Description: #{description}
      CTA Button Text: "#{cta_text}"
      #{value_prop.present? ? "Value Proposition: #{value_prop}" : ""}

      === DESIGN REQUIREMENTS ===
      - Use Bootstrap 5 for responsive design
      - Professional, modern design
      #{brand_colors.any? ? "- Brand colors: #{brand_colors.join(', ')}" : ""}
      - Mobile-responsive with smooth scrolling
      - Include hero section with compelling headline and CTA
      - Add sections for features/benefits
      - Include contact form (name, email, phone fields)
      - Professional styling with custom CSS

      === WEBSITE CONTEXT ===
      #{@website.present? ? "This page is part of the '#{@website.name}' website." : ""}
      #{@website&.theme.present? ? "Website theme: #{@website.theme}" : ""}

      === TECHNICAL REQUIREMENTS ===
      - Complete HTML document (<!DOCTYPE html> to </html>)
      - Use Bootstrap 5 via CDN
      - Include Font Awesome for icons
      - Form uses class="contact-form" with NO inline JS
      - NO action attribute on forms
      - Each input needs a unique name attribute
      - Use single quotes for JS strings containing HTML attributes
      - MUST complete all sections and include </body></html>

      Return ONLY the complete HTML.
      Make it conversion-optimized and feel custom-made for this business.
    PROMPT

    call_ai(prompt)
  end

  # ═══════════════════════════════════════════════════════════════
  # HELPERS
  # ═══════════════════════════════════════════════════════════════

  def call_ai(prompt)
    messages = [{ role: "user", content: prompt }]

    response = @ai_service.complete(
      messages: messages,
      max_tokens: 8192,
      temperature: 0.7,
      model: 'claude-sonnet-4-6'
    )

    html = if response.is_a?(Hash)
      response[:content] || response["content"] || response.dig(:message, :content) || ""
    else
      response.to_s
    end

    # Strip markdown code blocks if AI wrapped the HTML
    html = html.gsub(/\A```html?\s*\n?/i, '').gsub(/\n?```\s*\z/, '')
    html = html.strip

    # Ensure we have valid HTML
    unless html.include?("<!DOCTYPE") || html.include?("<html")
      html = "<!DOCTYPE html><html><head><title>Page</title></head><body>#{html}</body></html>"
    end

    html
  end

  def infer_purpose(template, title, description)
    combined = "#{title} #{description}".downcase

    # Explicit functional keywords
    if FUNCTIONAL_TEMPLATES.include?(template)
      return "functional"
    end

    # Check for functional intent in description
    functional_keywords = %w[
      dashboard tracker planner manager admin panel
      portal tool editor viewer settings account profile
      task board kanban calendar schedule inventory
      crm pipeline workflow inbox notifications report
      analytics chart table data grid crud create edit
    ]

    if functional_keywords.any? { |kw| combined.include?(kw) }
      return "functional"
    end

    # Marketing keywords
    marketing_keywords = %w[
      landing promotion campaign offer discount signup
      newsletter subscribe lead register promo launch
      testimonial pricing hero cta conversion
    ]

    if marketing_keywords.any? { |kw| combined.include?(kw) }
      return "marketing"
    end

    # Default: marketing templates are marketing, everything else context-dependent
    MARKETING_TEMPLATES.include?(template) ? "marketing" : "functional"
  end

  def infer_template(title, description)
    combined = "#{title} #{description}".downcase

    return "dashboard" if combined.match?(/dashboard|overview|summary|analytics/)
    return "form" if combined.match?(/\bform\b|create\s|add\s|new\s|submit|register/)
    return "list" if combined.match?(/\blist\b|table|browse|search|directory/)
    return "calendar" if combined.match?(/calendar|schedule|planner/)
    return "kanban" if combined.match?(/kanban|board|tracker|task/)
    return "settings" if combined.match?(/settings|config|preferences|account/)
    return "detail" if combined.match?(/detail|view\b|profile|single/)
    return "homepage" if combined.match?(/home|main|index|welcome/)
    return "landing" if combined.match?(/landing|promo|marketing/)

    "content"
  end

  def template_guidelines(template)
    case template
    when "dashboard"
      <<~GUIDE
        - Top summary cards with key metrics (numbers, percentages, trends)
        - Chart placeholders (use simple CSS/SVG charts or indicate chart area)
        - Recent activity or event feed
        - Quick action buttons
        - Status overview section
      GUIDE
    when "form"
      <<~GUIDE
        - Clean form layout with labeled fields
        - Group related fields into sections with headers
        - Include validation indicators
        - Save/Submit and Cancel buttons
        - Optional sidebar with help text or tips
      GUIDE
    when "list"
      <<~GUIDE
        - Data table with sortable column headers
        - Search/filter bar at the top
        - Action buttons per row (Edit, View, Delete)
        - Pagination or "Load more"
        - Bulk action toolbar
        - "Add New" button in header
        - Empty state message when no data
      GUIDE
    when "detail"
      <<~GUIDE
        - Content organized in sections/tabs
        - Key info in a summary card at top
        - Related items or history in sidebar or below
        - Edit/Delete action buttons
        - Back navigation breadcrumb
      GUIDE
    when "settings"
      <<~GUIDE
        - Sidebar navigation for setting categories
        - Form fields for each setting
        - Toggle switches for boolean settings
        - Save changes button (sticky or at bottom)
        - Success/warning alerts
      GUIDE
    when "calendar"
      <<~GUIDE
        - Monthly/weekly/daily view toggle
        - Grid layout showing days
        - Event cards within day cells
        - "Add Event" button
        - Today highlight
        - Navigation arrows for month/week
      GUIDE
    when "kanban"
      <<~GUIDE
        - Horizontal columns (e.g., To Do, In Progress, Done)
        - Draggable cards within columns
        - Card shows: title, priority badge, assignee avatar, due date
        - "Add Card" button at bottom of each column
        - Column header with item count
        - Color-coded priority indicators
      GUIDE
    else
      <<~GUIDE
        - Clean content layout with clear sections
        - Navigation breadcrumb
        - Appropriate for the page's stated purpose
      GUIDE
    end
  end
end
