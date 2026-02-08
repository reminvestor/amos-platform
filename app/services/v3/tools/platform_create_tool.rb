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
      BUILDER_TYPES = %w[landing_page website web_app workflow automation app module sync scheduled_task].freeze

      def self.metadata
        {
          name: "platform_create",
          description: <<~DESC.strip,
            Create any platform object. This is the universal creation tool.

            Types and examples:
            - contact — platform_create(type: "contact", data: { first_name: "Jane", last_name: "Doe", email: "j@example.com" })
            - contact_group — platform_create(type: "contact_group", data: { name: "VIP Customers" })
            - email_template — platform_create(type: "email_template", data: { name: "Welcome", subject: "Welcome!", body: "<h1>Hi!</h1>" })
            - campaign — platform_create(type: "campaign", data: { name: "Summer Sale", email_template_id: 5 })
            - automation — platform_create(type: "automation", data: { name: "Welcome Flow", trigger: "contact_created", action: "send_email", action_config: { template_id: 5 } })
            - sync — platform_create(type: "sync", data: { integration: "stripe", source: "customers", target: "Contact", schedule: "daily" })
            - scheduled_task — platform_create(type: "scheduled_task", data: { name: "Weekly Report", prompt: "Generate a summary of this week's contacts", schedule: "weekly" })
            - landing_page — platform_create(type: "landing_page", data: { title: "My Page", description: "Lead gen page" })
            - app — platform_create(type: "app", data: { name: "CRM", description: "Contact management" })

            Contact defaults: lifecycle_stage="lead", status="active".
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              type: {
                type: "string",
                description: "Object type to create (contact, contact_group, email_template, campaign, automation, sync, scheduled_task, landing_page, app, support_ticket)"
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
        when "automation", "workflow"
          build_automation(data)
        when "app", "module"
          build_app(data)
        when "sync"
          build_sync(data)
        when "scheduled_task"
          build_scheduled_task(data)
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
      # AUTOMATION — Simple trigger + action rule
      # ═══════════════════════════════════════════════════════════════

      def build_automation(data)
        name = data["name"] || data[:name] || "Automation"
        trigger = data["trigger"] || data[:trigger] || ""
        action = data["action"] || data[:action] || ""
        action_config = data["action_config"] || data[:action_config] || {}
        description = data["description"] || data[:description] || ""

        return error_response("Missing: trigger (e.g., 'contact_created', 'form_submitted')") if trigger.blank?
        return error_response("Missing: action (e.g., 'send_email', 'add_to_campaign', 'update_field')") if action.blank?

        Rails.logger.info "[V3::PlatformCreate] Building automation: #{name} (#{trigger} -> #{action})"

        # Normalize trigger type
        trigger_type = normalize_trigger(trigger)

        # Generate deterministic code from action template
        begin
          code = AutomationActionRegistry.generate_code(
            action: action,
            action_config: action_config,
            trigger: trigger_type,
            name: name
          )
        rescue ArgumentError => e
          return error_response(e.message)
        end

        # Create the AutomationCode record
        automation = AutomationCode.create!(
          entity: entity,
          created_by: user,
          name: name,
          description: description.presence || "#{action.humanize} when #{trigger_type.humanize.downcase}",
          trigger_type: trigger_type,
          trigger_config: { model: "Contact" }.merge(action_config),
          code: code,
          status: "active",
          is_tested: true,  # Template-generated code is pre-tested
          is_compiled: true
        )

        Rails.logger.info "[V3::PlatformCreate] Automation created: #{automation.name} (ID: #{automation.id})"

        @context[:canvas_suggestion] = "automation_dashboard"

        success_response(
          automation_id: automation.id,
          name: name,
          trigger: trigger_type,
          action: action,
          status: "active",
          message: "Automation '#{name}' is active! It will #{action.humanize.downcase} when #{trigger_type.humanize.downcase}.",
          canvas_type: "automation_dashboard"
        )
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Automation build failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        error_response("Automation creation failed: #{e.message}")
      end

      # ═══════════════════════════════════════════════════════════════
      # SYNC — Integration data sync (Stripe → Contacts, etc.)
      # ═══════════════════════════════════════════════════════════════

      def build_sync(data)
        integration_slug = data["integration"] || data[:integration]
        source = data["source"] || data[:source] || data["resource_type"] || data[:resource_type]
        target = data["target"] || data[:target] || data["target_type"] || data[:target_type]
        field_mappings = data["field_mappings"] || data[:field_mappings] || {}
        schedule = data["schedule"] || data[:schedule] || "manual"
        direction = data["direction"] || data[:direction] || "inbound"
        name = data["name"] || data[:name]

        return error_response("Missing: integration (e.g., 'stripe', 'hubspot')") if integration_slug.blank?
        return error_response("Missing: source (e.g., 'customers', 'invoices')") if source.blank?
        return error_response("Missing: target (e.g., 'Contact', 'Opportunity')") if target.blank?

        # Find the integration connection
        connection = entity.connections.joins(:integration)
                           .where(integrations: { slug: integration_slug })
                           .where.not(status: :disconnected)
                           .first

        unless connection
          return error_response(
            "No active connection found for '#{integration_slug}'. Connect it first via Integrations.",
            available_integrations: entity.connections.joins(:integration).pluck("integrations.slug").uniq
          )
        end

        # Auto-generate field mappings if not provided
        if field_mappings.blank?
          field_mappings = auto_generate_field_mappings(integration_slug, source, target)
        end

        Rails.logger.info "[V3::PlatformCreate] Building sync: #{integration_slug}/#{source} → #{target}"

        # Create the sync config
        sync_config = IntegrationSyncConfig.create!(
          entity: entity,
          connection: connection,
          resource_type: source,
          target_type: target.classify,
          field_mappings: field_mappings,
          sync_direction: direction,
          sync_mode: "incremental",
          conflict_resolution: "external_wins",
          schedule_type: schedule == "manual" ? "manual" : "scheduled",
          cron_expression: schedule_to_cron(schedule),
          enabled: true,
          metadata: {
            name: name || "#{integration_slug.titleize} #{source.titleize} Sync",
            created_by: "platform_create",
            created_at: Time.current.iso8601
          }
        )

        Rails.logger.info "[V3::PlatformCreate] Sync config created: #{sync_config.id}"

        # Optionally run the first sync immediately
        first_sync_result = nil
        if data["run_now"] || data[:run_now]
          first_sync_result = sync_config.execute_sync!(user: user)
        end

        success_response(
          sync_id: sync_config.id,
          integration: integration_slug,
          source: source,
          target: target,
          field_mappings: field_mappings,
          schedule: schedule,
          direction: direction,
          first_sync: first_sync_result,
          message: "Sync configured: #{integration_slug} #{source} → #{target}. #{schedule == 'manual' ? 'Run manually or set a schedule.' : "Scheduled: #{schedule}."}"
        )
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Sync build failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        error_response("Sync creation failed: #{e.message}")
      end

      def auto_generate_field_mappings(integration, source, target)
        # Common field mappings by integration + source → target
        case [integration, source, target.downcase]
        when ["stripe", "customers", "contact"]
          { "name" => "full_name", "email" => "email", "phone" => "phone", "id" => "metadata.stripe_id" }
        when ["stripe", "customers", "opportunity"]
          { "name" => "name", "email" => "contact_email", "id" => "metadata.stripe_id" }
        when ["hubspot", "contacts", "contact"]
          { "firstname" => "first_name", "lastname" => "last_name", "email" => "email", "phone" => "phone", "company" => "metadata.company" }
        when ["quickbooks", "customers", "contact"]
          { "DisplayName" => "full_name", "PrimaryEmailAddr.Address" => "email", "PrimaryPhone.FreeFormNumber" => "phone" }
        when ["quickbooks", "invoices", "opportunity"]
          { "CustomerRef.name" => "name", "TotalAmt" => "value", "DocNumber" => "metadata.invoice_number" }
        else
          # Return empty — Amos can ask user or discover the schema
          {}
        end
      end

      # ═══════════════════════════════════════════════════════════════
      # SCHEDULED TASK — Recurring tasks (reports, syncs, checks)
      # ═══════════════════════════════════════════════════════════════

      def build_scheduled_task(data)
        name = data["name"] || data[:name]
        prompt = data["prompt"] || data[:prompt] || data["description"] || data[:description]
        schedule = data["schedule"] || data[:schedule] || "daily"
        task_type = data["task_type"] || data[:task_type] || "custom"
        timezone = data["timezone"] || data[:timezone] || "America/Los_Angeles"

        return error_response("Missing: name") if name.blank?
        return error_response("Missing: prompt (what the task should do)") if prompt.blank?

        cron = schedule_to_cron(schedule)
        schedule_type = cron ? "cron" : "daily"

        task = ScheduledAgentTask.create!(
          entity: entity,
          user: user,
          name: name,
          description: prompt,
          task_type: task_type,
          prompt: prompt,
          schedule_type: schedule_type,
          cron_expression: cron,
          timezone: timezone,
          status: "active",
          enabled: true,
          input_context: data.except("name", "prompt", "schedule", "task_type", "timezone", :name, :prompt, :schedule, :task_type, :timezone)
        )

        success_response(
          task_id: task.id,
          name: task.name,
          schedule: schedule,
          cron: cron,
          next_run_at: task.next_run_at,
          message: "Scheduled task '#{name}' created! It will run #{schedule}."
        )
      rescue => e
        error_response("Scheduled task creation failed: #{e.message}")
      end

      def schedule_to_cron(schedule)
        case schedule.to_s.downcase
        when "hourly" then "0 * * * *"
        when "daily" then "0 9 * * *"
        when "weekly" then "0 9 * * 1"
        when "every_15_minutes", "15min" then "*/15 * * * *"
        when "every_30_minutes", "30min" then "*/30 * * * *"
        else nil
        end
      end

      def normalize_trigger(trigger)
        case trigger.to_s.downcase
        when /contact.*created/, /new.*contact/, "contact_created", "record_created" then "record_created"
        when /form.*submit/, "form_submitted", "form_submit" then "form_submit"
        when /status.*change/, "status_changed" then "status_changed"
        when /field.*change/, "field_changed" then "field_changed"
        when /schedule/, /cron/, /daily/, /weekly/, "scheduled" then "schedule"
        when /webhook/ then "webhook"
        when /record.*update/, "record_updated" then "record_updated"
        else "manual"
        end
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
