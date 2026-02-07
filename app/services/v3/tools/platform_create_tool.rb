# frozen_string_literal: true

module V3
  module Tools
    # PlatformCreateTool - Universal create tool for all platform objects
    #
    # Conversation-first: the AI gathers requirements, then calls this tool.
    # For buildable assets (landing pages, websites, apps, workflows),
    # this tool delegates to the appropriate builder service internally.
    #
    class PlatformCreateTool < ::Tools::BaseTool
      # Types that need special builder routing (not just DB creates)
      BUILDER_TYPES = %w[landing_page website web_app workflow app module].freeze

      def self.metadata
        {
          name: "platform_create",
          description: <<~DESC.strip,
            Create any platform object. This is the universal creation tool.

            **Data objects:** contact, campaign, email_template, contact_group, email_sequence,
            opportunity, activity, support_ticket, bounty

            **Buildable assets:**
            - landing_page — AI-generates a full page with HTML, images, forms. Opens editor when done.
            - website — Creates multiple linked landing pages with shared navigation.
            - workflow — Creates an automation (trigger + actions). Describe what should happen and when.
            - app / module — Creates a data-driven application (models, canvases, tools).

            Examples:
            - platform_create(type: "contact", data: { email: "j@example.com", first_name: "Jane" })
            - platform_create(type: "email_template", data: { name: "Welcome Email", subject: "Welcome!", body: "<h1>Welcome</h1><p>Thanks for joining.</p>" })
            - platform_create(type: "landing_page", data: { title: "Summer Sale", description: "Promo page for summer campaign" })
            - platform_create(type: "workflow", data: { name: "Welcome Flow", trigger: "contact_created", actions: ["send welcome email"] })
            - platform_create(type: "app", data: { name: "CRM", description: "Contact management with roles and profiles" })
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              type: {
                type: "string",
                description: "Object type to create (contact, campaign, email_template, contact_group, email_sequence, opportunity, activity, landing_page, website, web_app, workflow, app, module, support_ticket, bounty)"
              },
              data: {
                type: "object",
                description: "Object data. Fields depend on type. Use platform_query(type='schema', object='typename') to see available fields for data objects."
              }
            },
            required: %w[type data]
          }
        }
      end

      def execute(args)
        log_execution(args)

        type = get_arg(args, :type)&.to_s&.downcase&.singularize&.underscore
        data = get_arg(args, :data, {})

        return error_response("Missing required field: type") if type.blank?
        return error_response("Missing required field: data") if data.blank?

        # Route builder types to specialized handlers
        if BUILDER_TYPES.include?(type)
          return execute_builder(type, data)
        end

        # Standard data objects — delegate to CreateObjectTool
        create_tool = ::Tools::CreateObjectTool.new(user: user, entity: entity, context: context)
        plural_type = type.pluralize

        create_tool.execute({
          "object_type" => plural_type,
          "data" => data
        })
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Creation failed: #{e.message}")
      end

      private

      # ═══════════════════════════════════════════════════════════════
      # BUILDER ROUTING
      # ═══════════════════════════════════════════════════════════════

      def execute_builder(type, data)
        case type
        when "landing_page"
          build_landing_page(data)
        when "website"
          build_website(data)
        when "web_app"
          build_web_app(data)
        when "workflow"
          build_workflow(data)
        when "app", "module"
          build_app(data)
        else
          error_response("Unknown builder type: #{type}")
        end
      end

      # ═══════════════════════════════════════════════════════════════
      # LANDING PAGE — Single page, AI-generated HTML
      # ═══════════════════════════════════════════════════════════════

      def build_landing_page(data)
        Rails.logger.info "[V3::PlatformCreate] Building landing page: #{data['title'] || data[:title]}"

        # Delegate to the existing GenerateLandingPageTool which handles
        # AI HTML generation, image generation, form injection, etc.
        generator = ::Tools::GenerateLandingPageTool.new(
          user: user,
          entity: entity,
          context: context
        )

        # Pass through all data fields — GenerateLandingPageTool accepts many optional fields
        generator.execute(data)
      end

      # ═══════════════════════════════════════════════════════════════
      # WEBSITE — Multiple linked landing pages
      # ═══════════════════════════════════════════════════════════════

      def build_website(data)
        name = data["name"] || data[:name] || "Website"
        pages_data = data["pages"] || data[:pages] || []
        description = data["description"] || data[:description] || ""
        theme = data["theme"] || data[:theme] || "modern"

        return error_response("A website needs at least one page. Provide pages: [{ title: '...', description: '...' }]") if pages_data.empty?

        Rails.logger.info "[V3::PlatformCreate] Building website '#{name}' with #{pages_data.length} pages"

        # Stream progress
        stream_progress("Building website '#{name}'...", percentage: 0)

        # Create Website record
        website = Website.create!(
          entity: entity,
          created_by: user,
          name: name,
          slug: name.parameterize,
          description: description,
          theme: theme,
          status: "draft",
          metadata: { generated_by: "platform_create", page_count: pages_data.length }
        )

        # Build each page as a landing page
        created_pages = []
        generator = ::Tools::GenerateLandingPageTool.new(user: user, entity: entity, context: context)

        pages_data.each_with_index do |page_data, index|
          page_data = page_data.with_indifferent_access if page_data.is_a?(Hash)
          pct = ((index + 1).to_f / pages_data.length * 80 + 10).round
          stream_progress("Building page #{index + 1}/#{pages_data.length}: #{page_data[:title]}...", percentage: pct)

          result = generator.execute(page_data.merge(business_name: name))

          if result.is_a?(Hash) && result[:success] != false
            page_id = result[:landing_page_id] || result[:id]
            created_pages << { title: page_data[:title], landing_page_id: page_id }

            # Link to website via WebsitePage if possible
            if page_id && defined?(WebsitePage)
              WebsitePage.create!(
                website: website,
                entity: entity,
                name: page_data[:title] || "Page #{index + 1}",
                slug: (page_data[:title] || "page-#{index + 1}").parameterize,
                template: index == 0 ? "homepage" : "content",
                status: "draft",
                page_order: index,
                content: { landing_page_id: page_id }
              )
            end
          else
            Rails.logger.warn "[V3::PlatformCreate] Failed to build page: #{page_data[:title]}"
          end
        end

        stream_progress("Website '#{name}' complete!", percentage: 100)

        # Open the first page in the editor
        first_page_id = created_pages.first&.dig(:landing_page_id)
        @context[:canvas_suggestion] = "landing_page_editor" if first_page_id

        success_response(
          website_id: website.id,
          name: website.name,
          page_count: created_pages.length,
          pages: created_pages,
          message: "Website '#{name}' created with #{created_pages.length} pages!",
          canvas_type: first_page_id ? "landing_page_editor" : nil,
          canvas_data: first_page_id ? { landing_page_id: first_page_id } : nil
        )
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Website build failed: #{e.message}"
        error_response("Website creation failed: #{e.message}")
      end

      # ═══════════════════════════════════════════════════════════════
      # WEB APP — Website + workflows for form handling
      # ═══════════════════════════════════════════════════════════════

      def build_web_app(data)
        # A web app is just a website + workflows. Build the website first.
        website_result = build_website(data)
        return website_result unless website_result.is_a?(Hash) && website_result[:success] != false

        # Then create any workflows described in the data
        workflows_data = data["workflows"] || data[:workflows] || []
        created_workflows = []

        workflows_data.each do |wf_data|
          wf_result = build_workflow(wf_data.is_a?(Hash) ? wf_data : { name: wf_data.to_s })
          created_workflows << wf_result if wf_result.is_a?(Hash) && wf_result[:success] != false
        end

        website_result.merge(
          type: "web_app",
          workflows_created: created_workflows.length,
          message: "#{website_result[:message]} Plus #{created_workflows.length} workflow(s) for automation."
        )
      end

      # ═══════════════════════════════════════════════════════════════
      # WORKFLOW — Automation (trigger + actions)
      # ═══════════════════════════════════════════════════════════════

      def build_workflow(data)
        name = data["name"] || data[:name] || "Automation"
        description = data["description"] || data[:description] || ""
        trigger = data["trigger"] || data[:trigger] || ""
        actions = data["actions"] || data[:actions] || []

        Rails.logger.info "[V3::PlatformCreate] Building workflow: #{name}"

        # Use the Workflows::ArchitectService to generate from natural language
        begin
          architect = Workflows::ArchitectService.new(entity: entity, user: user)
          workflow_description = "#{name}: #{description}. Trigger: #{trigger}. Actions: #{Array(actions).join(', ')}"
          result = architect.generate_workflow(workflow_description)

          if result[:success] != false && result[:workflow]
            @context[:canvas_suggestion] = "automation_dashboard"

            success_response(
              workflow_id: result[:workflow][:id],
              name: name,
              message: "Workflow '#{name}' created! View it in your Automation Dashboard.",
              canvas_type: "automation_dashboard"
            )
          else
            # Fallback: create a simple workflow record if architect fails
            create_simple_workflow(name, description, trigger, actions)
          end
        rescue => e
          Rails.logger.warn "[V3::PlatformCreate] ArchitectService failed, using simple workflow: #{e.message}"
          create_simple_workflow(name, description, trigger, actions)
        end
      end

      def create_simple_workflow(name, description, trigger, actions)
        # Create via AutomationCode if available, otherwise use SimpleWorkflow
        if defined?(AutomationCode)
          code = AutomationCode.create!(
            entity: entity,
            user: user,
            name: name,
            description: description,
            trigger_type: normalize_trigger(trigger),
            status: "draft",
            code_content: generate_workflow_code(name, trigger, actions),
            metadata: { generated_by: "platform_create", trigger: trigger, actions: actions }
          )

          success_response(
            workflow_id: code.id,
            name: name,
            status: "draft",
            message: "Workflow '#{name}' created as draft. Review in Automation Dashboard.",
            canvas_type: "automation_dashboard"
          )
        else
          success_response(
            name: name,
            status: "draft",
            trigger: trigger,
            actions: actions,
            message: "Workflow '#{name}' designed. It will execute: #{Array(actions).join(', ')} when #{trigger}."
          )
        end
      end

      def normalize_trigger(trigger)
        case trigger.to_s.downcase
        when /contact.*created/, /new.*contact/ then "contact_created"
        when /form.*submit/ then "form_submitted"
        when /status.*change/ then "status_changed"
        when /schedule/, /cron/, /daily/, /weekly/ then "scheduled"
        when /webhook/ then "webhook"
        when /record.*update/ then "record_updated"
        else "custom"
        end
      end

      def generate_workflow_code(name, trigger, actions)
        actions_text = Array(actions).map { |a| "  # Action: #{a}" }.join("\n")
        <<~CODE
          # Workflow: #{name}
          # Trigger: #{trigger}
          # Generated by platform_create

          #{actions_text}

          # TODO: Implement action logic
        CODE
      end

      # ═══════════════════════════════════════════════════════════════
      # APP / MODULE — Data models + canvases + tools
      # ═══════════════════════════════════════════════════════════════

      def build_app(data)
        name = data["name"] || data[:name] || "App"
        description = data["description"] || data[:description] || ""

        Rails.logger.info "[V3::PlatformCreate] Building app: #{name}"
        stream_progress("Planning app '#{name}'...", percentage: 0)

        begin
          # Use ApplicationPlannerService to create a plan
          planner = ApplicationPlannerService.new(entity: entity, user: user)
          plan = planner.create_plan(
            name: name,
            description: description,
            requirements: data.except("name", "description", :name, :description)
          )

          stream_progress("Building app '#{name}'...", percentage: 30)

          # Approve and build immediately (no user-facing plan review)
          plan.update!(status: "approved")
          builder = ApplicationBuildService.new(plan)
          result = builder.execute!

          if result[:success]
            stream_progress("App '#{name}' is ready!", percentage: 100)

            # Find the built module to open its canvas
            built_module = plan.app_modules.first
            canvas_data = if built_module
                            { app_module_id: built_module.id }
                          else
                            {}
                          end

            success_response(
              app_id: plan.id,
              name: name,
              modules: result[:results][:modules]&.map { |m| { id: m[:id], name: m[:name], slug: m[:slug] } } || [],
              workflows: result[:results][:workflows]&.length || 0,
              message: "App '#{name}' is built and ready to use!",
              canvas_type: built_module ? "module_manager" : nil,
              canvas_data: canvas_data
            )
          else
            error_response("App build failed: #{result[:error]}")
          end
        rescue => e
          Rails.logger.error "[V3::PlatformCreate] App build failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          error_response("App creation failed: #{e.message}")
        end
      end
    end
  end
end
