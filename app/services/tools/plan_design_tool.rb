# frozen_string_literal: true

module Tools
  # PlanDesignTool creates a visual plan/blueprint for a landing page or website
  # before the actual build. This follows the "Plan → Build" pattern.
  #
  # Flow:
  # 1. User describes what they want in natural language
  # 2. AI generates a structured plan (sections, colors, content ideas)
  # 3. Plan is shown visually in the App Designer canvas
  # 4. User can refine the plan
  # 5. "Build" generates the actual HTML
  #
  class PlanDesignTool < BaseTool
    def self.metadata
      {
        name: 'plan_design',
        description: 'Create a visual plan/blueprint for a landing page or website. Use this when a user ' \
                     'describes what they want to build. Returns a structured plan showing sections, colors, ' \
                     'layout, and content ideas that the user can review and refine before building.',
        category: 'design',
        input_schema: {
          type: 'object',
          properties: {
            description: {
              type: 'string',
              description: 'What the user wants to build (e.g., "a landing page for my law enforcement training program")'
            },
            design_type: {
              type: 'string',
              enum: %w[landing_page website portfolio single_page],
              description: 'Type of design to plan. Defaults to landing_page.'
            },
            action: {
              type: 'string',
              enum: %w[create refine build],
              description: "Action: 'create' new plan, 'refine' existing plan, 'build' from plan"
            },
            plan_id: {
              type: 'integer',
              description: 'ID of existing plan to refine or build (optional)'
            },
            refinements: {
              type: 'object',
              description: 'Changes to make to the plan',
              properties: {
                add_section: { type: 'string', description: 'Section type to add' },
                remove_section: { type: 'string', description: 'Section name to remove' },
                update_colors: { type: 'object', description: 'Color scheme changes' },
                update_section: { type: 'object', description: 'Changes to a specific section' }
              }
            },
            # Optional hints from user
            color_preference: {
              type: 'string',
              description: 'Preferred color scheme (e.g., "dark and professional", "bright and modern")'
            },
            style_preference: {
              type: 'string',
              description: 'Preferred style (e.g., "minimalist", "bold", "corporate")'
            },
            reference_url: {
              type: 'string',
              description: 'URL of a reference site for inspiration'
            }
          },
          required: ['description']
        }
      }
    end

    def execute(args)
      log_execution(args)

      action = get_arg(args, :action) || 'create'

      case action
      when 'create'
        create_plan(args)
      when 'refine'
        refine_plan(args)
      when 'build'
        build_from_plan(args)
      else
        error_response("Unknown action: #{action}")
      end
    end

    private

    # ============================================
    # CREATE PLAN
    # ============================================

    def create_plan(args)
      description = get_arg(args, :description)
      design_type = get_arg(args, :design_type) || 'landing_page'
      color_preference = get_arg(args, :color_preference)
      style_preference = get_arg(args, :style_preference)
      reference_url = get_arg(args, :reference_url)

      unless description.present?
        return error_response("Please describe what you want to build")
      end

      # Generate the plan using AI
      ai_service = BedrockService.new
      plan_data = generate_plan_with_ai(
        ai_service,
        description: description,
        design_type: design_type,
        color_preference: color_preference,
        style_preference: style_preference,
        reference_url: reference_url
      )

      # Create a DesignPlan record to track this
      design_plan = DesignPlan.create!(
        entity: entity,
        user: user,
        name: plan_data[:name] || "New #{design_type.titleize}",
        design_type: design_type,
        description: description,
        plan_data: plan_data,
        status: 'draft'
      )

      # Broadcast to canvas
      broadcast_plan_to_canvas(design_plan)

      success_response(
        plan_id: design_plan.id,
        name: design_plan.name,
        design_type: design_type,
        plan: plan_data,
        status: 'draft',
        message: "📋 Here's your design plan for '#{design_plan.name}'",
        canvas_loaded: true,
        next_steps: [
          "Review the sections and layout below",
          "Tell me if you want to add, remove, or change any sections",
          "Say 'build it' when you're ready to generate the actual page"
        ]
      )
    rescue => e
      Rails.logger.error "PlanDesignTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to create plan: #{e.message}")
    end

    # ============================================
    # REFINE PLAN
    # ============================================

    def refine_plan(args)
      plan_id = get_arg(args, :plan_id)
      refinements = get_arg(args, :refinements) || {}

      design_plan = find_plan(plan_id)
      return design_plan if design_plan.is_a?(Hash) # Error response

      unless design_plan.status == 'draft'
        return error_response("This plan has already been built and cannot be modified")
      end

      # Apply refinements
      plan_data = design_plan.plan_data.deep_dup

      if refinements[:add_section].present?
        section = generate_section(refinements[:add_section])
        plan_data['sections'] ||= []
        plan_data['sections'] << section
      end

      if refinements[:remove_section].present?
        plan_data['sections']&.reject! { |s| s['name'] == refinements[:remove_section] }
      end

      if refinements[:update_colors].present?
        plan_data['color_scheme'] = plan_data['color_scheme'].merge(refinements[:update_colors])
      end

      if refinements[:update_section].present?
        section_name = refinements[:update_section][:name]
        updates = refinements[:update_section].except(:name)
        section = plan_data['sections']&.find { |s| s['name'] == section_name }
        section&.merge!(updates.stringify_keys) if section
      end

      design_plan.update!(plan_data: plan_data)

      # Broadcast updated plan
      broadcast_plan_to_canvas(design_plan)

      success_response(
        plan_id: design_plan.id,
        name: design_plan.name,
        plan: plan_data,
        status: design_plan.status,
        message: "✏️ Plan updated!",
        canvas_loaded: true
      )
    end

    # ============================================
    # BUILD FROM PLAN
    # ============================================

    def build_from_plan(args)
      plan_id = get_arg(args, :plan_id)

      design_plan = find_plan(plan_id)
      return design_plan if design_plan.is_a?(Hash) # Error response

      # Mark as building
      design_plan.update!(status: 'building')

      # Generate the actual landing page using the existing tool
      generate_tool = Tools::GenerateLandingPageTool.new(
        user: user,
        entity: entity,
        context: @context
      )

      # Convert plan to generation args
      plan_data = design_plan.plan_data
      generation_args = {
        title: plan_data['name'],
        description: design_plan.description,
        design_style: plan_data['style'],
        color_scheme: format_color_scheme(plan_data['color_scheme']),
        # Pass section structure as hints
        key_details: {
          sections: plan_data['sections']&.map { |s| s['name'] },
          layout: plan_data['layout'],
          content_hints: plan_data['sections']&.map { |s| { name: s['name'], content: s['content_ideas'] } }
        }
      }

      result = generate_tool.execute(generation_args)

      if result[:success]
        design_plan.update!(
          status: 'completed',
          landing_page_id: result[:id]
        )

        success_response(
          plan_id: design_plan.id,
          landing_page_id: result[:id],
          message: "🎉 Your landing page has been built!",
          canvas_action: 'open_landing_page_editor',
          canvas_data: { landing_page_id: result[:id] }
        )
      else
        design_plan.update!(status: 'failed', error_message: result[:error])
        error_response("Build failed: #{result[:error]}")
      end
    end

    # ============================================
    # AI PLAN GENERATION
    # ============================================

    def generate_plan_with_ai(ai_service, description:, design_type:, color_preference:, style_preference:, reference_url:)
      system_prompt = <<~SYSTEM
        You are a web design architect. Given a description, create a detailed plan/blueprint 
        for a #{design_type}.
        
        Return a JSON object with this exact structure:
        {
          "name": "Short name for this design",
          "style": "Overall style description",
          "layout": "single-column" | "two-column" | "grid" | "magazine",
          "color_scheme": {
            "primary": "#hex color",
            "secondary": "#hex color",
            "accent": "#hex color",
            "background": "#hex color",
            "text": "#hex color"
          },
          "typography": {
            "headings": "Font family name",
            "body": "Font family name"
          },
          "sections": [
            {
              "name": "Section identifier (e.g., hero, features, testimonials)",
              "type": "hero | features | benefits | testimonials | pricing | cta | contact | about | gallery | faq | stats | team | footer",
              "position": 1,
              "content_ideas": "Brief description of what content should go here",
              "layout_hint": "Layout suggestion for this section",
              "background": "light | dark | gradient | image"
            }
          ],
          "special_elements": ["List of special elements to include, e.g., video, animation, countdown"],
          "tone": "Tone of voice for content"
        }
        
        Consider:
        - The target audience and purpose
        - Modern design best practices
        - Mobile responsiveness
        - Conversion optimization
        
        #{color_preference.present? ? "Color preference: #{color_preference}" : ""}
        #{style_preference.present? ? "Style preference: #{style_preference}" : ""}
        #{reference_url.present? ? "Reference URL for inspiration: #{reference_url}" : ""}
        
        Return ONLY valid JSON, no markdown or explanation.
      SYSTEM

      user_message = "Create a design plan for: #{description}"

      messages = [{ role: 'user', content: user_message }]
      response = ai_service.send_message(system_prompt, messages, model: 'qwen3-next-80b', max_tokens: 4096, json_mode: true)

      # Parse JSON response
      json_str = response.to_s.strip
      json_str = json_str.gsub(/```json\n?/, '').gsub(/```\n?/, '') # Strip markdown
      
      JSON.parse(json_str)
    rescue JSON::ParserError => e
      Rails.logger.warn "Failed to parse plan JSON: #{e.message}"
      # Return a default structure
      {
        'name' => 'New Design',
        'style' => 'Modern and Professional',
        'layout' => 'single-column',
        'color_scheme' => {
          'primary' => '#6366f1',
          'secondary' => '#818cf8',
          'accent' => '#f59e0b',
          'background' => '#ffffff',
          'text' => '#1f2937'
        },
        'typography' => {
          'headings' => 'Inter',
          'body' => 'Inter'
        },
        'sections' => [
          { 'name' => 'hero', 'type' => 'hero', 'position' => 1, 'content_ideas' => 'Main headline and CTA', 'background' => 'gradient' },
          { 'name' => 'features', 'type' => 'features', 'position' => 2, 'content_ideas' => 'Key features or benefits', 'background' => 'light' },
          { 'name' => 'cta', 'type' => 'cta', 'position' => 3, 'content_ideas' => 'Call to action', 'background' => 'dark' }
        ],
        'special_elements' => [],
        'tone' => 'Professional'
      }
    end

    def generate_section(section_type)
      {
        'name' => section_type,
        'type' => section_type,
        'position' => 99, # Will be sorted
        'content_ideas' => "New #{section_type} section",
        'background' => 'light'
      }
    end

    def format_color_scheme(color_scheme)
      return nil unless color_scheme
      
      parts = []
      parts << "Primary: #{color_scheme['primary']}" if color_scheme['primary']
      parts << "Secondary: #{color_scheme['secondary']}" if color_scheme['secondary']
      parts << "Accent: #{color_scheme['accent']}" if color_scheme['accent']
      parts << "Background: #{color_scheme['background']}" if color_scheme['background']
      parts.join(', ')
    end

    # ============================================
    # HELPERS
    # ============================================

    def find_plan(plan_id)
      if plan_id.present?
        plan = DesignPlan.find_by(id: plan_id, entity_id: entity.id)
        return error_response("Plan not found") unless plan
        plan
      else
        # Find most recent draft plan
        plan = DesignPlan.where(entity_id: entity.id, user_id: user.id, status: 'draft')
                        .order(created_at: :desc)
                        .first
        return error_response("No active plan found. Describe what you want to build.") unless plan
        plan
      end
    end

    def broadcast_plan_to_canvas(design_plan)
      session_id = @context[:session_id] if @context
      return unless session_id

      ActionCable.server.broadcast(
        "scout_channel_#{session_id}",
        {
          type: 'canvas_load',
          canvas_type: 'app_designer',
          canvas_title: "Design: #{design_plan.name}",
          canvas_data: {
            plan_id: design_plan.id,
            plan: design_plan.plan_data,
            status: design_plan.status
          }
        }
      )
    end
  end
end
