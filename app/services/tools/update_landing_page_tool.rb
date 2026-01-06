module Tools
  class UpdateLandingPageTool < BaseTool
    def self.metadata
      {
        name: "update_landing_page_content",
        description: "Update content of existing landing pages using AI",
        category: "landing_page",
        input_schema: {
          type: "object",
          properties: {
            landing_page_id: {
              type: "integer",
              description: "ID of the landing page to update"
            },
            instruction: {
              type: "string",
              description: "Natural language instruction for how to update the page"
            }
          },
          required: [ "landing_page_id", "instruction" ]
        }
      }
    end

    def execute(args)
      log_execution(args)

      landing_page_id = get_arg(args, :landing_page_id)
      instruction = get_arg(args, :instruction)

      # Validate required args
      if error = validate_required_args(args, [ :landing_page_id, :instruction ])
        return error
      end

      begin
        # Use model-level ownership check for security
        landing_page = LandingPage.find_editable(landing_page_id, user: user, entity: entity)

        # Create automatic backup before updating
        landing_page.create_version_backup("Automatic backup before AI update")

        # Generate updated content using AI
        ai_service = BedrockService.new

        system_prompt = <<~SYSTEM
          You are an expert landing page designer. Update the HTML content based on the user's instructions.
          
          CRITICAL RULES FOR FORMS:
          - NEVER modify, remove, or break existing <form> elements
          - NEVER add inline JavaScript to forms (like onclick, onsubmit)
          - Keep form structure exactly: <form>, <input>, <button type="submit">
          - If user asks to fix a form, use this EXACT structure:
            <form>
              <div class="mb-3">
                <input type="text" name="name" class="form-control" placeholder="Your Name" required>
              </div>
              <div class="mb-3">
                <input type="email" name="email" class="form-control" placeholder="Your Email" required>
              </div>
              <div class="mb-3">
                <input type="tel" name="phone" class="form-control" placeholder="Your Phone">
              </div>
              <button type="submit" class="btn btn-primary w-100">Submit</button>
            </form>
          - Form handling JavaScript is injected separately - DO NOT add any form JS
        SYSTEM

        user_prompt = <<~PROMPT
          Current landing page HTML:
          #{landing_page.html_content}

          User instruction: #{instruction}

          Generate the updated HTML content following these rules:
          1. Maintain the existing Bootstrap classes and structure
          2. CRITICAL: Keep all <form> elements simple and clean - NO inline JavaScript
          3. Apply the requested changes precisely
          4. Ensure mobile responsiveness is maintained
          5. Return ONLY the raw HTML (no markdown code blocks like ```html)
          6. Start with <!DOCTYPE html> and end with </html>
        PROMPT

        # Use Claude Sonnet 4.5 for quality landing page updates (good balance of quality & cost)
        Rails.logger.info "🚀 Using Claude Sonnet 4.5 for landing page update"
        raw_response = ai_service.send_message(system_prompt, user_prompt, model: 'claude-sonnet-4-5', max_tokens: 25000)
        
        # Strip markdown code blocks if AI wrapped the HTML
        updated_html = strip_markdown_wrapper(raw_response)
        
        # Sanitize forms to remove problematic inline JavaScript
        updated_html = sanitize_forms(updated_html)
        
        # Ensure HTML has proper structure (closing tags)
        updated_html = ensure_html_structure(updated_html)

        # Update the landing page
        landing_page.update!(
          html_content: updated_html,
          metadata: landing_page.metadata.merge(
            last_ai_update: Time.current.iso8601,
            last_update_instruction: instruction,
            updated_by_ai: true
          )
        )

        # Broadcast canvas reload to refresh the editor
        # Find the user's recent sessions
        # Use subquery approach to avoid PostgreSQL DISTINCT/ORDER BY conflict
        recent_messages = ScoutMessage.where(user_id: user.id)
                                     .order(created_at: :desc)
                                     .limit(50)
                                     
        recent_sessions = recent_messages.pluck(:session_id).uniq.take(5)
                                     
        Rails.logger.info "🔍 Broadcasting canvas reload for landing page #{landing_page.id} to sessions: #{recent_sessions.inspect}"
        
        # Broadcast canvas reload to all recent sessions
        recent_sessions.each do |session_id|
          begin
            ScoutChannel.broadcast_to(session_id, {
              type: 'load_canvas',
              canvas: 'landing_page_editor',
              canvas_data: { landing_page_id: landing_page.id },
              force_refresh: true,
              message: "Landing page has been updated successfully!"
            })
            Rails.logger.info "📡 Broadcast canvas reload to session: #{session_id}"
          rescue => e
            Rails.logger.warn "⚠️  Failed to broadcast to session #{session_id}: #{e.message}"
          end
        end

        success_response(
          id: landing_page.id,
          title: landing_page.title,
          updated: true,
          backup_created: true,
          version_count: landing_page.landing_page_versions.count,
          message: "Successfully updated landing page content"
        )
      rescue ActiveRecord::RecordNotFound
        error_response("Landing page not found with ID: #{landing_page_id}")
      rescue SecurityError => e
        error_response("Not authorized: #{e.message}")
      rescue => e
        Rails.logger.error "Landing page update failed: #{e.message}"
        error_response("Failed to update landing page: #{e.message}")
      end
    end
    
    private
    
    def strip_markdown_wrapper(html)
      # Remove markdown code block wrappers: ```html ... ``` or ``` ... ```
      cleaned = html.to_s.strip

      # Remove starting code block (case insensitive)
      cleaned = cleaned.sub(/\A```html\s*\n?/i, "")
      cleaned = cleaned.sub(/\A```\s*\n?/, "")

      # Remove ending code block
      cleaned = cleaned.sub(/\n?```\s*\z/, "")

      cleaned.strip
    end
    
    def sanitize_forms(html)
      return html unless html.present?
      
      cleaned = html.dup
      
      # Remove inline event handlers from forms and form elements
      cleaned = cleaned.gsub(/\s+on\w+\s*=\s*["'][^"']*["']/i, '')
      cleaned = cleaned.gsub(/\s+on\w+\s*=\s*[^\s>]+/i, '')
      
      # Remove ALL action attributes from forms - we handle submission via JS
      cleaned = cleaned.gsub(/<form([^>]*)\s+action\s*=\s*["'][^"']*["']([^>]*)>/i, '<form\1\2>')
      
      # Remove method="get" - our JS uses POST
      cleaned = cleaned.gsub(/<form([^>]*)\s+method\s*=\s*["']get["']([^>]*)>/i, '<form\1\2>')
      
      # Remove JavaScript pseudo-URLs from any remaining actions
      cleaned = cleaned.gsub(/action\s*=\s*["']javascript:[^"']*["']/i, '')
      
      # Remove script tags inside forms
      cleaned = cleaned.gsub(/<form[^>]*>.*?<script.*?<\/script>.*?<\/form>/mi) do |match|
        match.gsub(/<script.*?<\/script>/mi, '')
      end
      
      # Ensure form has proper structure - fix unclosed form tags
      form_count = cleaned.scan(/<form[^>]*>/i).length
      close_form_count = cleaned.scan(/<\/form>/i).length
      
      if form_count > close_form_count
        Rails.logger.warn "⚠️ Found #{form_count} form opens but only #{close_form_count} closes"
        missing = form_count - close_form_count
        missing.times do
          if cleaned.include?('</body>')
            cleaned = cleaned.sub('</body>', "</form>\n</body>")
          else
            cleaned += "\n</form>"
          end
        end
      end
      
      Rails.logger.info "✅ Form sanitization complete for update"
      cleaned
    rescue => e
      Rails.logger.warn "Form sanitization failed: #{e.message}"
      html
    end
    
    def ensure_html_structure(html)
      return html unless html.present?
      
      result = html.dup
      
      # Check for and fix missing closing tags
      has_body_close = result.include?("</body>")
      has_html_close = result.include?("</html>")
      
      unless has_body_close
        if has_html_close
          result = result.sub("</html>", "</body>\n</html>")
        else
          result = "#{result}\n</body>\n</html>"
        end
        Rails.logger.warn "⚠️ Added missing </body> tag to landing page HTML"
      end
      
      unless has_html_close
        result = "#{result}\n</html>"
        Rails.logger.warn "⚠️ Added missing </html> tag to landing page HTML"
      end
      
      result
    end
  end
end
