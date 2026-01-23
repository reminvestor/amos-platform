module Tools
  class EditLandingPageSectionTool < BaseTool
    # Section types that can be identified and edited
    SECTION_TYPES = %w[
      hero header features benefits pricing testimonials 
      cta contact about footer social faq stats team 
      gallery video newsletter
    ].freeze

    def self.metadata
      {
        name: "edit_landing_page_section",
        description: "Edit a specific section of a landing page without rewriting the whole page. Much faster and more precise than full-page updates. Use this for targeted edits like 'change the hero headline', 'add a testimonial', 'update CTA button text', etc.",
        category: "landing_page",
        input_schema: {
          type: "object",
          properties: {
            landing_page_id: {
              type: "integer",
              description: "ID of the landing page to edit"
            },
            section: {
              type: "string",
              description: "Which section to edit: hero, header, features, benefits, pricing, testimonials, cta, contact, about, footer, social, faq, stats, team, gallery, video, newsletter. Use 'custom' with css_selector for non-standard sections."
            },
            action: {
              type: "string",
              enum: %w[replace update add remove],
              description: "Action to perform: 'replace' (swap entire section), 'update' (modify specific elements), 'add' (insert new content), 'remove' (delete section)"
            },
            content: {
              type: "string",
              description: "New HTML content for the section (required for replace/add). For 'update' action, describe what to change."
            },
            instruction: {
              type: "string",
              description: "Natural language instruction for what to change (used with 'update' action). E.g., 'Change the headline to Welcome to Our Platform'"
            },
            position: {
              type: "string",
              enum: %w[before after inside_start inside_end],
              description: "For 'add' action: where to place new content relative to the section"
            },
            css_selector: {
              type: "string",
              description: "CSS selector for custom targeting (e.g., '.custom-section', '#unique-block')"
            }
          },
          required: %w[landing_page_id section action]
        }
      }
    end

    def execute(args)
      log_execution(args)

      landing_page_id = get_arg(args, :landing_page_id)
      section = get_arg(args, :section)&.downcase
      action = get_arg(args, :action)&.downcase
      content = get_arg(args, :content)
      instruction = get_arg(args, :instruction)
      position = get_arg(args, :position) || 'inside_end'
      css_selector = get_arg(args, :css_selector)

      # Validate required args
      return error_response("landing_page_id is required") unless landing_page_id
      return error_response("section is required") unless section
      return error_response("action is required") unless action
      return error_response("action must be one of: replace, update, add, remove") unless %w[replace update add remove].include?(action)

      # Content validation based on action
      if %w[replace add].include?(action) && content.blank?
        return error_response("content is required for #{action} action")
      end
      
      if action == 'update' && instruction.blank? && content.blank?
        return error_response("instruction or content is required for update action")
      end

      begin
        # Use model-level ownership check for security
        landing_page = LandingPage.find_editable(landing_page_id, user: user, entity: entity)
        
        # Create automatic backup before editing
        landing_page.create_version_backup("Before section edit: #{section}")
        
        # Parse current HTML
        html = landing_page.html_content
        
        case action
        when 'replace'
          updated_html = replace_section(html, section, content, css_selector)
        when 'update'
          updated_html = update_section(html, section, instruction || content, css_selector)
        when 'add'
          updated_html = add_to_section(html, section, content, position, css_selector)
        when 'remove'
          updated_html = remove_section(html, section, css_selector)
        end
        
        return error_response("Section '#{section}' not found in landing page") if updated_html.nil?
        
        # Sanitize and save
        updated_html = sanitize_forms(updated_html)
        
        landing_page.update!(
          html_content: updated_html,
          metadata: landing_page.metadata.merge(
            last_section_edit: Time.current.iso8601,
            last_edited_section: section,
            last_edit_action: action
          )
        )
        
        # Broadcast canvas reload
        broadcast_canvas_reload(landing_page)
        
        success_response(
          id: landing_page.id,
          title: landing_page.title,
          section_edited: section,
          action: action,
          updated: true,
          backup_created: true,
          message: "Successfully #{action}d the #{section} section"
        )
        
      rescue ActiveRecord::RecordNotFound
        error_response("Landing page not found with ID: #{landing_page_id}")
      rescue SecurityError => e
        error_response("Not authorized: #{e.message}")
      rescue => e
        Rails.logger.error "Landing page section edit failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Failed to edit section: #{e.message}")
      end
    end

    private

    # Find section in HTML using multiple strategies
    def find_section(html, section_name, css_selector = nil)
      doc = Nokogiri::HTML(html)
      
      # Strategy 1: CSS selector if provided
      if css_selector.present?
        element = doc.at_css(css_selector)
        return element if element
      end
      
      # Strategy 2: Look for section comment markers
      # <!-- SECTION: hero --> ... <!-- END: hero -->
      if html.include?("<!-- SECTION: #{section_name}")
        start_marker = "<!-- SECTION: #{section_name} -->"
        end_marker = "<!-- END: #{section_name} -->"
        return { type: :comment_markers, start: start_marker, end: end_marker }
      end
      
      # Strategy 3: Semantic HTML5 elements with data attributes
      element = doc.at_css("[data-section='#{section_name}']") ||
                doc.at_css("section[data-section='#{section_name}']") ||
                doc.at_css("div[data-section='#{section_name}']")
      return element if element
      
      # Strategy 4: Common class/id patterns
      patterns = [
        "##{section_name}",
        ".#{section_name}",
        ".#{section_name}-section",
        "##{section_name}-section",
        "section.#{section_name}",
        "div.#{section_name}",
        "[class*='#{section_name}']"
      ]
      
      patterns.each do |pattern|
        element = doc.at_css(pattern)
        return element if element
      end
      
      # Strategy 5: Semantic detection based on content
      element = detect_section_semantically(doc, section_name)
      return element if element
      
      nil
    end
    
    # Detect sections based on common patterns
    def detect_section_semantically(doc, section_name)
      case section_name
      when 'hero'
        # Hero is usually the first major section with a big heading
        doc.at_css('header + section') || 
        doc.at_css('section:first-of-type') ||
        doc.at_css('.hero, .jumbotron, .banner, [class*="hero"]')
      when 'header', 'nav'
        doc.at_css('header') || doc.at_css('nav')
      when 'footer'
        doc.at_css('footer')
      when 'cta'
        doc.at_css('[class*="cta"], [class*="call-to-action"], .action-section')
      when 'features'
        doc.at_css('[class*="feature"], .services, [class*="services"]')
      when 'testimonials'
        doc.at_css('[class*="testimonial"], [class*="review"], [class*="client"]')
      when 'pricing'
        doc.at_css('[class*="pricing"], [class*="plans"]')
      when 'contact'
        doc.at_css('[class*="contact"], form.contact-form')&.parent || 
        doc.at_css('.contact-section')
      when 'about'
        doc.at_css('[class*="about"]')
      when 'faq'
        doc.at_css('[class*="faq"], [class*="questions"]')
      else
        nil
      end
    end

    # Replace entire section
    def replace_section(html, section_name, new_content, css_selector = nil)
      section = find_section(html, section_name, css_selector)
      return nil unless section
      
      if section.is_a?(Hash) && section[:type] == :comment_markers
        # Replace between markers
        regex = /#{Regexp.escape(section[:start])}.*?#{Regexp.escape(section[:end])}/m
        wrapped_content = "#{section[:start]}\n#{new_content}\n#{section[:end]}"
        html.gsub(regex, wrapped_content)
      else
        # Replace Nokogiri element
        doc = Nokogiri::HTML(html)
        element = find_section_element(doc, section_name, css_selector)
        return nil unless element
        
        element.replace(new_content)
        doc.to_html
      end
    end

    # Update section with AI assistance
    def update_section(html, section_name, instruction, css_selector = nil)
      doc = Nokogiri::HTML(html)
      element = find_section_element(doc, section_name, css_selector)
      return nil unless element
      
      section_html = element.to_html
      
      # Use AI to update just this section
      ai_service = BedrockService.new(user: user, entity: entity)
      
      system_prompt = <<~SYSTEM
        You are a surgical HTML editor. You receive a section of a landing page and an edit instruction.
        
        RULES:
        - Make ONLY the requested change
        - Preserve all existing structure, classes, and styling
        - Do NOT add any new features or content not requested
        - Do NOT remove any existing content not mentioned
        - Return ONLY the updated section HTML (no markdown, no explanation)
        - Preserve data-section attributes if present
        
        STYLING RULES (Critical):
        - For color/style changes, use INLINE STYLES on specific elements
        - NEVER add or modify <style> tags - this affects the whole page
        - NEVER add CSS rules - only inline style attributes
        - Example: To change a link color, add style="color: #ff0000;" to that specific <a> tag
        - If asked to change "link colors in footer", only change <a> tags within this section
        - Do NOT change CSS variables or global styles
      SYSTEM
      
      user_prompt = <<~PROMPT
        CURRENT SECTION (#{section_name}):
        #{section_html}
        
        EDIT INSTRUCTION: #{instruction}
        
        Return the updated section HTML only.
      PROMPT
      
      updated_section = ai_service.send_message(system_prompt, user_prompt, model: 'qwen3-next-80b', max_tokens: 8192)
      updated_section = strip_markdown_wrapper(updated_section)
      
      element.replace(updated_section)
      doc.to_html
    end

    # Add content to section
    def add_to_section(html, section_name, content, position, css_selector = nil)
      doc = Nokogiri::HTML(html)
      element = find_section_element(doc, section_name, css_selector)
      return nil unless element
      
      case position
      when 'before'
        element.add_previous_sibling(content)
      when 'after'
        element.add_next_sibling(content)
      when 'inside_start'
        element.prepend_child(content)
      when 'inside_end'
        element.add_child(content)
      end
      
      doc.to_html
    end

    # Remove section
    def remove_section(html, section_name, css_selector = nil)
      section = find_section(html, section_name, css_selector)
      return nil unless section
      
      if section.is_a?(Hash) && section[:type] == :comment_markers
        # Remove between markers (including markers)
        regex = /#{Regexp.escape(section[:start])}.*?#{Regexp.escape(section[:end])}/m
        html.gsub(regex, '')
      else
        doc = Nokogiri::HTML(html)
        element = find_section_element(doc, section_name, css_selector)
        return nil unless element
        
        element.remove
        doc.to_html
      end
    end

    # Helper to find element for Nokogiri operations
    def find_section_element(doc, section_name, css_selector = nil)
      if css_selector.present?
        return doc.at_css(css_selector)
      end
      
      # Try all strategies
      element = doc.at_css("[data-section='#{section_name}']") ||
                doc.at_css("section[data-section='#{section_name}']") ||
                doc.at_css("##{section_name}") ||
                doc.at_css(".#{section_name}") ||
                doc.at_css(".#{section_name}-section") ||
                doc.at_css("section.#{section_name}") ||
                detect_section_semantically(doc, section_name)
      
      element
    end

    def strip_markdown_wrapper(html)
      cleaned = html.to_s.strip
      cleaned = cleaned.sub(/\A```html\s*\n?/i, "")
      cleaned = cleaned.sub(/\A```\s*\n?/, "")
      cleaned = cleaned.sub(/\n?```\s*\z/, "")
      cleaned.strip
    end

    def sanitize_forms(html)
      return html unless html.present?
      
      cleaned = html.dup
      cleaned = cleaned.gsub(/\s+on\w+\s*=\s*["'][^"']*["']/i, '')
      cleaned = cleaned.gsub(/\s+on\w+\s*=\s*[^\s>]+/i, '')
      cleaned = cleaned.gsub(/<form([^>]*)\s+action\s*=\s*["'][^"']*["']([^>]*)>/i, '<form\1\2>')
      cleaned
    rescue => e
      Rails.logger.warn "Form sanitization failed: #{e.message}"
      html
    end

    def broadcast_canvas_reload(landing_page)
      recent_messages = ScoutMessage.where(user_id: user.id)
                                    .order(created_at: :desc)
                                    .limit(50)
      recent_sessions = recent_messages.pluck(:session_id).uniq.take(5)
      
      recent_sessions.each do |session_id|
        begin
          ScoutChannel.broadcast_to(session_id, {
            type: 'load_canvas',
            canvas: 'landing_page_editor',
            canvas_data: { landing_page_id: landing_page.id },
            force_refresh: true,
            message: "Section updated successfully!"
          })
        rescue => e
          Rails.logger.warn "Failed to broadcast to session #{session_id}: #{e.message}"
        end
      end
    end
  end
end

