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
        landing_page = LandingPage.find_by!(id: landing_page_id, entity: entity)

        # Create automatic backup before updating
        landing_page.create_version_backup("Automatic backup before AI update")

        # Generate updated content using AI
        ai_service = BedrockService.new

        system_prompt = "You are an expert landing page designer. Update the HTML content based on the user's instructions while maintaining the existing structure and design system."

        user_prompt = <<~PROMPT
          Current landing page HTML:
          #{landing_page.html_content}

          User instruction: #{instruction}

          Generate the updated HTML content following these rules:
          1. Maintain the existing Bootstrap classes and structure
          2. Keep all forms functional with the same action URLs
          3. Apply the requested changes precisely
          4. Ensure mobile responsiveness is maintained
          5. Return only the updated HTML, no explanations
        PROMPT

        updated_html = ai_service.send_message(system_prompt, user_prompt)

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
              canvas_name: 'landing_page_editor',
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
      rescue => e
        Rails.logger.error "Landing page update failed: #{e.message}"
        error_response("Failed to update landing page: #{e.message}")
      end
    end
  end
end
