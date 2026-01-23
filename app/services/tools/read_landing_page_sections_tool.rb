module Tools
  class ReadLandingPageSectionsTool < BaseTool
    def self.metadata
      {
        name: "read_landing_page_sections",
        description: "Analyze a landing page and identify all its sections with their content summary. Use this before editing to understand the page structure. Returns section names, types, and brief descriptions.",
        category: "landing_page",
        input_schema: {
          type: "object",
          properties: {
            landing_page_id: {
              type: "integer",
              description: "ID of the landing page to analyze"
            },
            include_content: {
              type: "boolean",
              description: "If true, include a text summary of each section's content. Default: true"
            }
          },
          required: ["landing_page_id"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      landing_page_id = get_arg(args, :landing_page_id)
      include_content = get_arg(args, :include_content) != false

      return error_response("landing_page_id is required") unless landing_page_id

      begin
        landing_page = LandingPage.find_editable(landing_page_id, user: user, entity: entity)
        
        html = landing_page.html_content
        sections = analyze_sections(html, include_content)
        
        success_response(
          id: landing_page.id,
          title: landing_page.title,
          slug: landing_page.slug,
          status: landing_page.status,
          total_sections: sections.length,
          sections: sections,
          tips: [
            "Use 'edit_landing_page_section' with section name to make targeted edits",
            "Use 'update' action with instruction for AI-assisted changes",
            "Use 'replace' action with HTML content for direct replacement"
          ]
        )

      rescue ActiveRecord::RecordNotFound
        error_response("Landing page not found with ID: #{landing_page_id}")
      rescue SecurityError => e
        error_response("Not authorized: #{e.message}")
      rescue => e
        Rails.logger.error "Landing page analysis failed: #{e.message}"
        error_response("Failed to analyze landing page: #{e.message}")
      end
    end

    private

    def analyze_sections(html, include_content)
      doc = Nokogiri::HTML(html)
      sections = []

      # Find all section-like elements
      section_candidates = []
      
      # 1. Elements with data-section attribute
      doc.css('[data-section]').each do |el|
        section_candidates << { element: el, name: el['data-section'], source: 'data-section' }
      end
      
      # 2. Semantic HTML5 sections
      doc.css('header, nav, main, section, article, aside, footer').each do |el|
        # Skip if already captured by data-section
        next if section_candidates.any? { |s| s[:element] == el }
        
        name = detect_section_name(el)
        section_candidates << { element: el, name: name, source: 'semantic' } if name
      end
      
      # 3. Common class patterns
      common_patterns = %w[
        hero jumbotron banner features benefits pricing testimonials 
        reviews cta call-to-action contact about team faq gallery 
        portfolio clients partners stats newsletter social services
      ]
      
      common_patterns.each do |pattern|
        doc.css("[class*='#{pattern}']").each do |el|
          # Skip if already captured or if it's a child of an already-captured section
          next if section_candidates.any? { |s| s[:element] == el || s[:element].ancestors.include?(el) }
          next if el.ancestors.any? { |a| section_candidates.any? { |s| s[:element] == a } }
          
          section_candidates << { element: el, name: pattern, source: 'class' }
        end
      end
      
      # 4. Look for comment markers
      if html.include?('<!-- SECTION:')
        html.scan(/<!-- SECTION: (\w+) -->/).each do |match|
          sections << {
            name: match[0],
            type: match[0],
            source: 'comment_marker',
            editable: true,
            content_summary: "(marked section)"
          }
        end
      end
      
      # Process candidates into sections
      section_candidates.each do |candidate|
        el = candidate[:element]
        name = candidate[:name]
        
        section_info = {
          name: name,
          type: categorize_section(name),
          source: candidate[:source],
          tag: el.name,
          classes: el['class']&.split(' ')&.first(3)&.join(' '),
          id: el['id'],
          editable: true
        }
        
        if include_content
          section_info[:content_summary] = summarize_content(el)
          section_info[:has_form] = el.at_css('form').present?
          section_info[:has_images] = el.css('img').any?
          section_info[:has_video] = el.css('video, iframe[src*="youtube"], iframe[src*="vimeo"]').any?
          section_info[:buttons] = el.css('button, .btn, a.btn').map { |b| b.text.strip }.first(3)
          
          # Include parent container info for layout context
          parent_info = analyze_parent_layout(el)
          section_info[:parent_layout] = parent_info if parent_info
        end
        
        sections << section_info unless sections.any? { |s| s[:name] == name }
      end
      
      sections
    end

    def detect_section_name(element)
      # Try to determine section name from various attributes
      return element['data-section'] if element['data-section']
      return element['id'] if element['id'].present?
      
      # Check classes for common section patterns
      classes = element['class']&.split(' ') || []
      common_names = %w[hero header nav footer features testimonials pricing cta contact about faq gallery]
      
      classes.each do |cls|
        common_names.each do |name|
          return name if cls.downcase.include?(name)
        end
      end
      
      # Fall back to element type
      case element.name
      when 'header' then 'header'
      when 'nav' then 'nav'
      when 'footer' then 'footer'
      when 'main' then 'main'
      when 'section'
        # Try to infer from first heading
        heading = element.at_css('h1, h2, h3')
        if heading
          heading.text.strip.downcase.gsub(/[^a-z0-9]+/, '_').first(20)
        else
          'section'
        end
      else
        nil
      end
    end

    def categorize_section(name)
      name = name.to_s.downcase
      
      case name
      when /hero|jumbotron|banner|intro/
        'hero'
      when /header|nav/
        'navigation'
      when /feature|service/
        'features'
      when /benefit/
        'benefits'
      when /price|pricing|plan/
        'pricing'
      when /testimonial|review|client/
        'testimonials'
      when /cta|call.*action|action/
        'cta'
      when /contact|form/
        'contact'
      when /about|story/
        'about'
      when /team|member/
        'team'
      when /faq|question/
        'faq'
      when /gallery|portfolio|work/
        'gallery'
      when /footer/
        'footer'
      when /social/
        'social'
      when /stat|number|metric/
        'stats'
      else
        'content'
      end
    end

    def summarize_content(element)
      # Extract key text content
      text = element.text.gsub(/\s+/, ' ').strip
      
      # Get headings
      headings = element.css('h1, h2, h3').map { |h| h.text.strip }.first(2)
      
      if headings.any?
        summary = headings.join(' | ')
        summary += " + #{(text.split.length - headings.join(' ').split.length).clamp(0, 500)} words" if text.length > 100
        summary.truncate(150)
      else
        text.truncate(100)
      end
    end
    
    # Analyze parent containers to detect layout issues
    def analyze_parent_layout(element)
      parent = element.parent
      return nil unless parent && parent.name != 'body' && parent.name != 'html'
      
      parent_classes = parent['class']&.split(' ') || []
      grandparent = parent.parent
      grandparent_classes = grandparent&.[]('class')&.split(' ') || []
      
      layout_info = {}
      
      # Detect Bootstrap grid
      if parent_classes.any? { |c| c =~ /^col(-\w+)?(-\d+)?$/ }
        layout_info[:type] = 'bootstrap_column'
        layout_info[:column_class] = parent_classes.find { |c| c =~ /^col/ }
        layout_info[:in_row] = grandparent_classes.include?('row')
        layout_info[:warning] = "Section is inside a Bootstrap column - layout changes may require editing parent row/container"
      end
      
      # Detect flexbox
      if parent_classes.any? { |c| c.include?('flex') || c.include?('d-flex') }
        layout_info[:type] = 'flexbox'
        layout_info[:flex_classes] = parent_classes.select { |c| c.include?('flex') || c.include?('d-flex') }
        layout_info[:warning] = "Section is inside a flex container - layout changes may require editing parent"
      end
      
      # Detect CSS grid
      if parent_classes.any? { |c| c.include?('grid') }
        layout_info[:type] = 'css_grid'
        layout_info[:warning] = "Section is inside a CSS grid - layout changes may require editing parent"
      end
      
      # Detect two-column or sidebar layouts
      siblings = parent.parent&.css('> *')&.length || 1
      if siblings > 1
        layout_info[:siblings] = siblings
        layout_info[:multi_column_layout] = true
        layout_info[:warning] ||= "Section appears to be in a multi-column layout (#{siblings} columns) - use update_landing_page_content for major layout changes"
      end
      
      # Include parent selector for advanced edits
      if layout_info.any?
        parent_selector = []
        parent_selector << parent.name
        parent_selector << "##{parent['id']}" if parent['id'].present?
        parent_selector << ".#{parent_classes.first}" if parent_classes.any?
        layout_info[:parent_selector] = parent_selector.join
        layout_info[:parent_classes] = parent_classes.first(3).join(' ')
      end
      
      layout_info.presence
    end
  end
end

