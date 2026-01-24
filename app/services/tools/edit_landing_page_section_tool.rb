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
        description: "Edit a specific section of a landing page. SIMPLE USAGE: Just provide landing_page_id, section (hero/header/features/etc), and instruction (what to change in plain English). Example: edit_landing_page_section(landing_page_id: 166, section: 'hero', instruction: 'Change the background color to dark blue')",
        category: "landing_page",
        input_schema: {
          type: "object",
          properties: {
            landing_page_id: {
              type: "integer",
              description: "ID of the landing page to edit (check canvas context if viewing one)"
            },
            section: {
              type: "string",
              description: "Section name: hero, header, features, benefits, pricing, testimonials, cta, contact, about, footer"
            },
            instruction: {
              type: "string",
              description: "What to change in plain English. E.g., 'Make the background darker', 'Change headline to Welcome', 'Add a phone number field'"
            },
            action: {
              type: "string",
              enum: %w[update replace add remove],
              description: "Action type. Default is 'update' which uses the instruction to modify. Only change if you need to replace entire HTML, add content, or remove a section."
            },
            content: {
              type: "string",
              description: "Raw HTML content (only needed for 'replace' or 'add' actions)"
            }
          },
          required: %w[landing_page_id section instruction]
        }
      }
    end

    def execute(args)
      log_execution(args)

      landing_page_id = get_arg(args, :landing_page_id)
      section = get_arg(args, :section)&.downcase
      action = get_arg(args, :action)&.downcase || 'update'  # Default to update
      content = get_arg(args, :content)
      instruction = get_arg(args, :instruction)
      position = get_arg(args, :position) || 'inside_end'
      css_selector = get_arg(args, :css_selector)
      include_parent_context = get_arg(args, :include_parent_context)
      
      # Auto-detect if parent context is needed based on instruction keywords
      layout_keywords = %w[full-width fullwidth full\ width center centered column columns side sidebar layout position move reposition take\ up whole\ page]
      if instruction.present? && layout_keywords.any? { |kw| instruction.downcase.include?(kw) }
        include_parent_context = true
        Rails.logger.info "🔧 [EditSection] Auto-enabling parent context for layout-related instruction"
      end

      # Validate required args
      return error_response("landing_page_id is required") unless landing_page_id
      return error_response("section is required") unless section
      return error_response("instruction is required for update action") if action == 'update' && instruction.blank?
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
          updated_html = update_section(html, section, instruction || content, css_selector, include_parent_context)
        when 'add'
          updated_html = add_to_section(html, section, content, position, css_selector)
        when 'remove'
          updated_html = remove_section(html, section, css_selector)
        end
        
        return error_response("Section '#{section}' not found in landing page") if updated_html.nil?
        
        # Check if the HTML actually changed
        html_changed = updated_html != html
        
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
        
        # Log the change for debugging
        if html_changed
          Rails.logger.info "✅ [EditSection] Landing page #{landing_page.id} section '#{section}' updated successfully"
        else
          Rails.logger.warn "⚠️ [EditSection] No actual change detected in HTML for landing page #{landing_page.id} section '#{section}'"
        end
        
        # Broadcast canvas reload
        broadcast_canvas_reload(landing_page)
        
        # Include verification info in response
        response_data = {
          id: landing_page.id,
          title: landing_page.title,
          section_edited: section,
          action: action,
          updated: true,
          html_changed: html_changed,
          backup_created: true,
          message: html_changed ? 
            "Successfully #{action}d the #{section} section" : 
            "Section processed but no changes detected - the section may already have the requested properties or the change couldn't be applied"
        }
        
        # Warn if no actual change was made
        if !html_changed
          response_data[:warning] = "The HTML content did not change. This could mean: 1) The section already had these properties, 2) The change couldn't be applied due to CSS conflicts, or 3) The AI didn't make the requested modification."
        end
        
        success_response(response_data)
        
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
    def update_section(html, section_name, instruction, css_selector = nil, include_parent_context = false)
      doc = Nokogiri::HTML(html)
      element = find_section_element(doc, section_name, css_selector)
      return nil unless element
      
      section_html = element.to_html
      
      # For layout changes, try a SAFE approach first - only modify CSS classes on parent
      if include_parent_context
        layout_fixed = try_safe_layout_fix(doc, element, instruction)
        if layout_fixed
          Rails.logger.info "🔧 [EditSection] Applied safe layout fix (CSS class changes only)"
          return doc.to_html
        end
        Rails.logger.info "🔧 [EditSection] Safe layout fix not applicable, falling back to AI edit of section only"
      end
      
      # Use AI to update the SECTION ONLY (never the parent - it's too risky)
      ai_service = BedrockService.new(user: user, entity: entity)
      
      system_prompt = <<~SYSTEM
        You are a surgical HTML editor. You receive a section of a landing page and an edit instruction.
        
        ## CRITICAL PRESERVATION RULES:
        - Make ONLY the requested change - nothing more
        - PRESERVE all existing content (text, headings, descriptions)
        - PRESERVE all existing URLs (src attributes, href attributes) - NEVER change URLs
        - PRESERVE all existing video elements - keep the exact same src
        - PRESERVE all existing image elements - keep the exact same src
        - PRESERVE all existing classes and CSS styling (unless specifically asked to change them)
        - PRESERVE all existing inline styles - do NOT remove or significantly change them
        - Do NOT add any new features or content not requested
        - Do NOT remove any existing content not explicitly requested
        - Return ONLY the updated section HTML (no markdown, no explanation, no code fences)
        - Preserve data-section attributes if present
        
        ## 🚫 FORBIDDEN ACTIONS - NEVER DO THESE:
        - NEVER add width: 100%, max-width: 100%, or margin: 0 to sections
        - NEVER add position: relative/absolute to section containers
        - NEVER add padding: 0 to sections (it removes spacing)
        - NEVER change the overall structure/container of the section
        - Layout/width issues are handled separately - just edit CONTENT
        
        ## WHAT YOU CAN DO:
        - Edit text content (headlines, paragraphs, button text)
        - Change colors using inline styles on SPECIFIC elements (not containers)
        - Reorder elements WITHIN the section
        - Change text-align on text elements
        - Update button styles
        
        ## STYLING RULES (Critical):
        - For color changes, add style="color: #xxx;" to the specific text element
        - For background changes, add style="background: #xxx;" to the specific element
        - NEVER add or modify <style> tags
        - NEVER add CSS rules - only inline style attributes on individual elements
      SYSTEM
      
      user_prompt = <<~PROMPT
        CURRENT SECTION (#{section_name}):
        #{section_html}
        
        EDIT INSTRUCTION: #{instruction}
        
        Return the updated section HTML only.
      PROMPT
      
      # send_message expects an array of message objects, not a string
      messages = [{ role: 'user', content: user_prompt }]
      updated_html_fragment = ai_service.send_message(system_prompt, messages, model: 'qwen3-next-80b', max_tokens: 8192)
      updated_html_fragment = strip_markdown_wrapper(updated_html_fragment)
      
      # Log for debugging
      Rails.logger.info "🔧 [EditSection] Original section size: #{section_html.length} chars"
      Rails.logger.info "🔧 [EditSection] Updated section size: #{updated_html_fragment.length} chars"
      
      # Verify the AI actually made a change
      if updated_html_fragment.strip == section_html.strip
        Rails.logger.warn "⚠️ [EditSection] AI returned identical HTML - no changes made!"
      end
      
      # For background color changes, handle CSS class conflicts
      if instruction.downcase.include?('background') || instruction.downcase.include?('bg-')
        updated_html_fragment = fix_background_class_conflicts(updated_html_fragment, instruction)
      end
      
      element.replace(updated_html_fragment)
      
      doc.to_html
    end
    
    # Fix CSS class conflicts for background color changes
    def fix_background_class_conflicts(html_fragment, instruction)
      doc = Nokogiri::HTML::DocumentFragment.parse(html_fragment)
      
      # Extract color from instruction (e.g., "#ece3de" or "ece3de")
      color_match = instruction.match(/#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b/)
      target_color = color_match ? "##{color_match[1]}" : nil
      
      return html_fragment unless target_color
      
      Rails.logger.info "🎨 [EditSection] Detected background color change to: #{target_color}"
      
      # Find elements with Bootstrap bg- classes that might conflict
      bg_classes = ['bg-dark', 'bg-black', 'bg-light', 'bg-white', 'bg-primary', 'bg-secondary', 'bg-success', 'bg-danger', 'bg-warning', 'bg-info']
      
      # Look at the root element and immediate children for background classes
      root = doc.children.first
      if root
        # Remove conflicting bg- classes from root element
        current_classes = root['class']&.split(' ') || []
        conflicting = current_classes & bg_classes
        
        if conflicting.any?
          Rails.logger.info "🎨 [EditSection] Removing conflicting classes: #{conflicting.join(', ')}"
          new_classes = current_classes - bg_classes
          root['class'] = new_classes.join(' ')
          
          # Ensure the inline style has the background with !important to override any remaining CSS
          existing_style = root['style'] || ''
          unless existing_style.include?('background')
            root['style'] = "#{existing_style}; background-color: #{target_color} !important;".gsub(/^;\s*/, '')
          end
        end
        
        # Also check for inline background-color that might not have been applied
        if root['style'].present? && root['style'].include?('background')
          # Make sure it has !important for override
          unless root['style'].include?('!important')
            root['style'] = root['style'].gsub(/background(-color)?:\s*([^;]+);?/) do |match|
              "#{match.chomp(';')} !important;"
            end
          end
        end
      end
      
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

    # Safe layout fix that only modifies CSS classes on parent elements
    # This is much safer than asking AI to rewrite entire parent containers
    def try_safe_layout_fix(doc, element, instruction)
      instruction_lower = instruction.downcase
      
      # Handle "full width" / "take up entire page" / "span full container" requests
      if instruction_lower.match?(/full[- ]?width|entire (page|container|width)|span (full|entire|whole)|take up (the )?full/)
        Rails.logger.info "🔧 [SafeLayoutFix] Detected full-width request"
        
        # Strategy 1: Look for flex-based grid layouts (section-edit-grid, grid-col)
        # These are common in the landing page editor
        flex_grid = element.at_css('.section-edit-grid') || element.ancestors('.section-edit-grid').first
        if flex_grid
          Rails.logger.info "🔧 [SafeLayoutFix] Found flex grid layout"
          
          # Make the grid single-column by changing flex-direction
          current_style = flex_grid['style'] || ''
          new_style = current_style
            .gsub(/flex-direction:\s*row\s*;?/i, '')
            .gsub(/flex-wrap:\s*wrap\s*;?/i, '')
          new_style = "#{new_style}; flex-direction: column; align-items: stretch;".gsub(/^;\s*/, '').gsub(/;\s*;/, ';')
          flex_grid['style'] = new_style
          
          # Make grid columns full width
          flex_grid.css('.grid-col').each do |col|
            col_style = col['style'] || ''
            new_col_style = col_style
              .gsub(/flex:\s*1\s*;?/i, '')
              .gsub(/min-width:\s*\d+px\s*;?/i, '')
            new_col_style = "#{new_col_style}; width: 100%; flex: none;".gsub(/^;\s*/, '').gsub(/;\s*;/, ';')
            col['style'] = new_col_style
          end
          
          Rails.logger.info "🔧 [SafeLayoutFix] Changed flex grid to single column"
          return true
        end
        
        # Strategy 2: Bootstrap column layout
        parent = element.parent
        grandparent = parent&.parent
        return false unless parent
        
        parent_classes = (parent['class'] || '').split(' ')
        grandparent_classes = (grandparent&.[]('class') || '').split(' ')
        
        parent_is_column = parent_classes.any? { |c| c =~ /^col(-\w+)?(-\d+)?$/ }
        grandparent_is_row = grandparent_classes.include?('row')
        
        if parent_is_column && grandparent_is_row
          # Scenario: section is in <div class="row"><div class="col-6">section</div>...</div>
          # Fix: Change col-X to col-12 on the parent
          
          new_classes = parent_classes.map do |c|
            # Replace any col-* with col-12
            if c =~ /^col(-\w+)?(-\d+)?$/
              if c =~ /^col-(\w+)-\d+$/
                "col-#{$1}-12"
              elsif c =~ /^col-\d+$/
                "col-12"
              else
                "col-12"
              end
            else
              c
            end
          end.uniq
          
          parent['class'] = new_classes.join(' ')
          
          # Hide empty sibling columns
          if grandparent
            grandparent.children.each do |sibling|
              next if sibling == parent || !sibling.element?
              sibling_text = sibling.text.strip
              sibling_children = sibling.children.select(&:element?).count
              
              if sibling_text.empty? || sibling_text.match?(/drop.*here|placeholder/i) || sibling_children == 0
                sibling['style'] = "#{sibling['style']}; display: none;"
                Rails.logger.info "🔧 [SafeLayoutFix] Hiding empty sibling column"
              end
            end
          end
          
          Rails.logger.info "🔧 [SafeLayoutFix] Changed column to col-12"
          return true
        end
        
        # If no known layout pattern, don't try - let the agent explain to user
        Rails.logger.info "🔧 [SafeLayoutFix] No recognized layout pattern, skipping safe fix"
        return false
      end
      
      # Handle "center" requests
      if instruction_lower.match?(/center|centred?|middle/)
        existing_style = element['style'] || ''
        unless existing_style.include?('text-align') || existing_style.include?('margin')
          element['style'] = "#{existing_style}; text-align: center; margin-left: auto; margin-right: auto;".gsub(/^; /, '')
          Rails.logger.info "🔧 [SafeLayoutFix] Added centering styles to section"
          return true
        end
      end
      
      false
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
      # Get session from context if available, otherwise find recent sessions
      session_id = context[:session_id] if context.present?
      
      if session_id.blank?
        recent_messages = ScoutMessage.where(user_id: user.id)
                                      .order(created_at: :desc)
                                      .limit(50)
        session_ids = recent_messages.pluck(:session_id).uniq.take(3)
      else
        session_ids = [session_id]
      end
      
      session_ids.each do |sid|
        begin
          # Broadcast a refresh event - the frontend will refresh the current canvas
          # if it's displaying this landing page
          ScoutChannel.broadcast_to(sid, {
            type: 'data_updated',
            resource_type: 'landing_page',
            resource_id: landing_page.id,
            message: "Landing page updated",
            force_refresh: true
          })
          Rails.logger.info "📡 [EditSection] Broadcast data_updated for landing page #{landing_page.id} to session #{sid}"
        rescue => e
          Rails.logger.warn "Failed to broadcast to session #{sid}: #{e.message}"
        end
      end
    end
  end
end

