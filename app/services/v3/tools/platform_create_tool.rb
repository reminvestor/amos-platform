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
      BUILDER_TYPES = %w[landing_page website web_app workflow automation app module sync scheduled_task integration custom_domain email_sequence].freeze

      def self.metadata
        {
          name: "platform_create",
          description: <<~DESC.strip,
            Create any platform object. Pass type and data.

            Types: contact, contact_group, email_template, campaign, automation, sync, integration, scheduled_task, landing_page, app, custom_domain, or any custom app type.

            Examples:
            - type: "contact", data: { first_name: "Jane", email: "j@example.com", lifecycle_stage: "customer" }
            - type: "contact", data: { contacts: [{first_name: "A", email: "a@b.com"}, {first_name: "B", email: "b@c.com"}] } (batch)
            - type: "contact_group", data: { name: "VIP Customers", contact_ids: [1, 2, 3] }
            - type: "contact_group", data: { name: "Leads", contact_emails: ["a@b.com", "c@d.com"] }
            - type: "email_template", data: { name: "Welcome", subject: "Welcome!", body: "<h1>Hi {{first_name}}!</h1><p>Your content here...</p>" }
            - type: "campaign", data: { name: "Summer Sale", email_template_id: 5 }
            - type: "automation", data: { name: "Welcome Flow", trigger: "contact_created", action: "send_email", action_config: { template_id: 5 } }
            - type: "landing_page", data: { title: "CloudSync Pro", description: "SaaS collaboration tool", business_info: { value_proposition: "Real-time collaboration for teams", key_benefits: ["Instant sync", "Smart scheduling", "Automated reports"], target_audience: "Remote teams" } }
            - type: "email_sequence", data: { name: "Welcome Series", emails: [{ subject: "Welcome!", body: "<h1>Hi {{first_name}}!</h1>...", delay_days: 0 }, { subject: "Getting Started", body: "...", delay_days: 3 }] }
            - type: "app", data: { name: "CRM", description: "Contact management" }

            Email sequence (one-call): pass 'emails' array to auto-create templates, contact group, sequence, and steps in one call.
            Automation triggers: contact_created, form_submit, record_updated, status_changed, field_changed, schedule, webhook
            Automation actions: send_email, add_to_campaign, update_field, create_activity, call_webhook, notify_user
            Contact fields: email (required), first_name, last_name, lifecycle_stage, status, phone, company, custom_fields.
            Contact group: name (required), contact_ids or contact_emails to add members.
            Landing page: title, description, business_info (value_proposition, key_benefits, target_audience), key_details (pricing, social_proof), design_style.
            Email template: name, subject, body (HTML with {{first_name}}, {{company}} merge tags).
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              type: {
                type: "string",
                description: "Object type to create (contact, contact_group, email_template, campaign, automation, sync, integration, scheduled_task, landing_page, app, support_ticket)"
              },
              data: {
                type: "object",
                description: "Object data. Fields depend on type — see examples above. Just pass the fields you have; unknown fields are auto-stored as custom_fields."
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

        # ═══ BATCH CREATE: detect plural array in data ═══
        # If data contains a "contacts", "email_templates", etc. array, batch-create all items.
        # This turns 10 tool calls into 1.
        plural_key = type.pluralize.to_s
        items_array = data[plural_key] || data[plural_key.to_sym] || data["items"] || data[:items]
        if items_array.is_a?(Array) && items_array.length > 1
          return batch_create(type, items_array, data)
        end

        # Route builder types to specialized handlers
        if BUILDER_TYPES.include?(type)
          return execute_builder(type, data)
        end

        # Check if type matches a dynamic module model
        module_result = find_and_create_module_record(type, data)
        return module_result if module_result

        # Standard data objects — delegate to CreateObjectTool
        create_tool = ::Tools::CreateObjectTool.new(user: user, entity: entity, context: context)
        plural_type = type.pluralize

        create_tool.execute({
          "object_type" => plural_type,
          "data" => data
        })
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        V3::AiErrorTransformer.transform(e, type: type, tool: "platform_create", data: data)
      end

      private

      # ═══════════════════════════════════════════════════════════════
      # BATCH CREATE — turn N tool calls into 1
      # ═══════════════════════════════════════════════════════════════

      def batch_create(type, items, parent_data = {})
        plural_type = type.pluralize
        create_tool = ::Tools::CreateObjectTool.new(user: user, entity: entity, context: context)

        # Shared fields from parent data (e.g., contact_group_ids, tags) applied to all items
        shared_fields = parent_data.except(plural_type, plural_type.to_sym, "items", :items)

        created = 0
        updated = 0
        errors_list = []

        items.each_with_index do |item_data, idx|
          item_data = item_data.merge(shared_fields) if shared_fields.any?
          begin
            result = create_tool.execute({ "object_type" => plural_type, "data" => item_data })
            if result.is_a?(Hash)
              if result[:updated] || result.dig(:data, :updated)
                updated += 1
              else
                created += 1
              end
            else
              created += 1
            end
          rescue => e
            errors_list << { index: idx, error: e.message }
          end
        end

        summary = "Batch #{plural_type}: #{created} created, #{updated} updated (existing)"
        summary += ", #{errors_list.length} failed" if errors_list.any?

        Rails.logger.info "[V3::PlatformCreate] #{summary}"

        success_response(
          object_type: plural_type,
          batch: true,
          total: items.length,
          created: created,
          updated: updated,
          failed: errors_list.length,
          errors: errors_list.first(5),  # Cap error details to avoid bloating response
          message: summary
        )
      end

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
        when "integration"
          build_integration(data)
        when "scheduled_task"
          build_scheduled_task(data)
        when "custom_domain"
          build_custom_domain(data)
        when "email_sequence"
          build_email_sequence(data)
        else
          error_response("Unknown builder type: #{type}")
        end
      end

      # ═══════════════════════════════════════════════════════════════
      # LANDING PAGE — Single page, AI-generated HTML
      # ═══════════════════════════════════════════════════════════════

      def build_landing_page(data)
        Rails.logger.info "[V3::PlatformCreate] Building landing page: #{data['title'] || data[:title]}"

        generator = ::Tools::GenerateLandingPageTool.new(
          user: user,
          entity: entity,
          context: context
        )

        # Enrich sparse data: if model only passed title/description, extract
        # structured content from the description so the generator has richer inputs.
        desc = (data["description"] || data[:description]).to_s
        if desc.length > 30 && (data["business_info"] || data[:business_info]).blank?
          data["content_focus"] ||= desc
        end

        generator.execute(data)
      end

      # ═══════════════════════════════════════════════════════════════
      # EMAIL SEQUENCE — One-call builder: creates templates + group + sequence + steps
      # ═══════════════════════════════════════════════════════════════

      def build_email_sequence(data)
        data = (data.is_a?(Hash) ? data : {}).deep_symbolize_keys
        name = data[:name] || "Email Sequence"
        emails = data[:emails] || data[:steps]

        unless emails.is_a?(Array) && emails.any?
          # Fall through to standard CreateObjectTool for simple sequence creation
          create_tool = ::Tools::CreateObjectTool.new(user: user, entity: entity, context: context)
          return create_tool.execute({ "object_type" => "email_sequences", "data" => data.stringify_keys })
        end

        Rails.logger.info "[V3::PlatformCreate] Building email sequence '#{name}' with #{emails.length} emails"

        created_templates = []
        emails.each_with_index do |email_data, idx|
          email_data = email_data.deep_symbolize_keys
          template_name = email_data[:name] || "#{name} - Email #{idx + 1}"
          subject = email_data[:subject] || template_name
          body = email_data[:body] || "<p>#{subject}</p>"

          template = entity.email_templates.find_by(name: template_name)
          template ||= EmailTemplate.create!(
            name: template_name,
            subject: subject,
            body: body,
            user: user,
            entity: entity
          )
          created_templates << template
        end

        # Auto-create or use provided contact group
        contact_group_id = data[:contact_group_id]
        unless contact_group_id
          group = entity.contact_groups.find_by(name: "#{name} Recipients")
          group ||= ContactGroup.create!(
            name: "#{name} Recipients",
            user: user,
            entity: entity
          )
          contact_group_id = group.id
        end

        sequence = EmailSequence.create!(
          name: name,
          goal: data[:goal],
          entity: entity,
          contact_group_id: contact_group_id,
          status: "draft"
        )

        created_templates.each_with_index do |template, idx|
          email_data = emails[idx].deep_symbolize_keys
          delay_hours = (email_data[:delay_days] || 0).to_i * 24
          delay_hours = email_data[:delay_hours].to_i if email_data[:delay_hours].present?

          SequenceStep.create!(
            email_sequence: sequence,
            email_template: template,
            step_number: idx + 1,
            delay_hours: delay_hours
          )
        end

        Rails.logger.info "[V3::PlatformCreate] Built email sequence '#{name}' (ID: #{sequence.id}) with #{created_templates.length} steps"

        success_response(
          object_type: "email_sequence",
          id: sequence.id,
          name: name,
          status: "draft",
          contact_group_id: contact_group_id,
          steps_created: created_templates.length,
          templates: created_templates.map { |t| { id: t.id, name: t.name, subject: t.subject } },
          message: "Email sequence '#{name}' created with #{created_templates.length} email(s). " \
                   "Templates, contact group, sequence, and steps are all set up. " \
                   "Add contacts to the group, then enroll them with platform_execute(action: 'enroll_sequence', sequence_id: #{sequence.id}).",
          next_actions: [
            "Add contacts to group: platform_update(type: 'contact_group', id: #{contact_group_id}, data: { contact_ids: [...] })",
            "Enroll contacts: platform_execute(action: 'enroll_sequence', sequence_id: #{sequence.id})"
          ]
        )
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Email sequence build failed: #{e.class}: #{e.message}"
        V3::AiErrorTransformer.transform(e, type: "email_sequence", tool: "platform_create", data: data)
      end

      # ═══════════════════════════════════════════════════════════════
      # WEBSITE — Multiple pages with proper functional/marketing distinction
      # ═══════════════════════════════════════════════════════════════

      def build_website(data)
        name = data["name"] || data[:name] || "Website"
        pages_data = data["pages"] || data[:pages] || []
        description = data["description"] || data[:description] || ""
        theme = data["theme"] || data[:theme] || "modern"
        page_purpose = data["page_purpose"] || data[:page_purpose] # "functional" or "marketing" — auto-detected if nil

        return error_response("A website needs at least one page. Provide pages: [{ title: '...', description: '...' }]") if pages_data.empty?

        Rails.logger.info "[V3::PlatformCreate] Building website '#{name}' with #{pages_data.length} pages (purpose: #{page_purpose || 'auto-detect'})"

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
          status: "draft"
        )

        # Use WebsitePageGeneratorService for proper page generation
        generator = WebsitePageGeneratorService.new(user: user, entity: entity, website: website)
        created_pages = []

        pages_data.each_with_index do |page_data, index|
          page_data = page_data.with_indifferent_access if page_data.is_a?(Hash)
          pct = ((index + 1).to_f / pages_data.length * 80 + 10).round
          stream_progress("Building page #{index + 1}/#{pages_data.length}: #{page_data[:title]}...", percentage: pct)

          # Pass the website-level page_purpose as default, but let individual pages override
          gen_data = page_data.merge(
            business_name: name,
            page_purpose: page_data[:page_purpose] || page_purpose
          )

          result = generator.generate(gen_data)

          if result[:success]
            # Map generator templates to valid WebsitePage templates
            gen_template = result[:template] || (index == 0 ? "homepage" : "content")
            template_map = { "dashboard" => "custom", "kanban" => "custom", "calendar" => "custom", "settings" => "custom" }
            template = template_map[gen_template] || (WebsitePage::TEMPLATES.include?(gen_template) ? gen_template : "custom")
            website_page = WebsitePage.create!(
              website: website,
              entity: entity,
              name: page_data[:title] || "Page #{index + 1}",
              slug: (page_data[:title] || "page-#{index + 1}").parameterize,
              template: template,
              html_content: result[:html_content],
              status: "draft",
              is_homepage: index == 0,
              show_in_nav: true,
              app_module_id: page_data[:app_module_id],
              is_dynamic: page_data[:is_dynamic] || false
            )

            created_pages << {
              title: page_data[:title],
              website_page_id: website_page.id,
              page_type: result[:page_type],
              template: template
            }
          else
            Rails.logger.warn "[V3::PlatformCreate] Failed to build page: #{page_data[:title]} — #{result[:error]}"
          end
        end

        stream_progress("Website '#{name}' complete!", percentage: 100)

        @context[:canvas_suggestion] = "my_creations"

        success_response(
          website_id: website.id,
          name: website.name,
          page_count: created_pages.length,
          pages: created_pages,
          message: "Website '#{name}' created with #{created_pages.length} pages!",
          canvas_type: "my_creations",
          canvas_data: { type: "website" }
        )
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Website build failed: #{e.message}"
        error_response("Website creation failed: #{e.message}")
      end

      # ═══════════════════════════════════════════════════════════════
      # WEB APP — Full external application: Website + Modules + Auth
      # ═══════════════════════════════════════════════════════════════

      def build_web_app(data)
        name = data["name"] || data[:name] || "Web App"
        description = data["description"] || data[:description] || ""
        auth_data = data["auth"] || data[:auth] || {}
        modules_data = data["modules"] || data[:modules] || []
        pages_data = data["pages"] || data[:pages] || []
        subdomain = data["subdomain"] || data[:subdomain] || name.parameterize

        Rails.logger.info "[V3::PlatformCreate] Building web app '#{name}' with #{pages_data.length} pages and #{modules_data.length} modules"

        stream_progress("Building web app '#{name}'...", percentage: 0)

        # Step 1: Build the website (pages)
        website = nil
        if pages_data.any?
          website_result = build_website(data)
          if website_result.is_a?(Hash) && website_result[:success] != false
            website = Website.find_by(id: website_result[:website_id])
          end
        end

        # Step 2: Create the WebApp record
        auth_config = {
          "methods" => auth_data["methods"] || auth_data[:methods] || ["email"],
          "allow_registration" => auth_data["allow_registration"] || auth_data[:allow_registration] || true,
          "require_email_verification" => auth_data["require_email_verification"] || auth_data[:require_email_verification] || false,
          "session_timeout" => auth_data["session_timeout"] || auth_data[:session_timeout] || 3600
        }

        web_app = WebApp.create!(
          entity: entity,
          created_by: user,
          name: name,
          slug: name.parameterize,
          description: description,
          subdomain: subdomain,
          status: "draft",
          website: website,
          auth_config: auth_config,
          features: data["features"] || data[:features] || {}
        )

        stream_progress("Linking modules...", percentage: 60)

        # Step 3: Link app modules
        linked_modules = []
        modules_data.each do |mod_ref|
          mod_ref = mod_ref.with_indifferent_access if mod_ref.is_a?(Hash)
          # Find module by slug, name, or ID
          mod = if mod_ref.is_a?(Hash)
            entity.app_modules.find_by(slug: mod_ref[:slug]) ||
            entity.app_modules.find_by(name: mod_ref[:name]) ||
            entity.app_modules.find_by(id: mod_ref[:id])
          else
            entity.app_modules.find_by(slug: mod_ref.to_s) ||
            entity.app_modules.find_by(name: mod_ref.to_s)
          end

          if mod
            wam = web_app.add_module!(mod, {
              is_public: mod_ref.is_a?(Hash) ? (mod_ref[:is_public] || false) : false,
              allow_create: mod_ref.is_a?(Hash) ? (mod_ref[:allow_create] || true) : true,
              allow_edit: mod_ref.is_a?(Hash) ? (mod_ref[:allow_edit] || true) : true,
              allow_delete: mod_ref.is_a?(Hash) ? (mod_ref[:allow_delete] || false) : false
            })
            linked_modules << mod.name if wam
          end
        end

        # Step 4: Create automations/workflows
        workflows_data = data["workflows"] || data[:workflows] || []
        created_workflows = []
        workflows_data.each do |wf_data|
          wf_data = wf_data.is_a?(Hash) ? wf_data : { name: wf_data.to_s }
          wf_result = build_automation(wf_data.merge("web_app_id" => web_app.id))
          created_workflows << wf_result if wf_result.is_a?(Hash) && wf_result[:success] != false
        end

        stream_progress("Web app '#{name}' complete!", percentage: 100)

        # Suggest loading the design preview
        @context[:canvas_suggestion] = "design_preview"

        success_response(
          web_app_id: web_app.id,
          website_id: website&.id,
          name: web_app.name,
          slug: web_app.slug,
          page_count: pages_data.length,
          module_count: linked_modules.length,
          linked_modules: linked_modules,
          workflows_created: created_workflows.length,
          message: "Web app '#{name}' created and available in the platform! #{linked_modules.any? ? "Linked modules: #{linked_modules.join(', ')}." : ''} #{pages_data.any? ? "#{pages_data.length} page(s) built." : ''} Open the preview to see it.".strip,
          canvas_type: "design_preview",
          canvas_data: { web_app_id: web_app.id, preview_type: "web_app" }
        )
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Web app build failed: #{e.message}"
        error_response("Web app creation failed: #{e.message}")
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
        integration = data["integration"] || data[:integration]

        return error_response("Missing: trigger (e.g., 'contact_created', 'form_submitted', 'stripe.customer_created')") if trigger.blank?
        return error_response("Missing: action (e.g., 'send_email', 'add_to_campaign', 'create_contact')") if action.blank?

        Rails.logger.info "[V3::PlatformCreate] Building automation: #{name} (#{trigger} -> #{action})"

        # ═══ Integration trigger resolution ═══
        # If the trigger looks like an integration event (e.g., "stripe.customer_created"),
        # resolve it to the correct webhook trigger config
        integration_trigger = AutomationActionRegistry.resolve_integration_trigger(trigger)
        
        if integration_trigger
          trigger_type = integration_trigger[:trigger_type]  # "webhook"
          integration ||= integration_trigger[:integration]
          action_config = action_config.merge(
            "event_filter" => integration_trigger[:event_filter],
            "integration" => integration
          )
          
          # Auto-populate field mappings for create_contact if not provided
          if action == "create_contact" && (action_config["field_mappings"].blank? && action_config[:field_mappings].blank?)
            source = data["source"] || data[:source] || infer_source_from_trigger(trigger)
            defaults = AutomationActionRegistry.default_field_mappings(integration, source)
            action_config["field_mappings"] = defaults if defaults.any?
          end
        else
          trigger_type = normalize_trigger(trigger)
        end

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

        # Build trigger config
        trigger_config_hash = { model: "Contact" }.merge(action_config)
        if integration_trigger
          trigger_config_hash[:integration] = integration
          trigger_config_hash[:event_filter] = integration_trigger[:event_filter]
          trigger_config_hash[:webhook_path] = "#{integration}/#{integration_trigger[:event_filter]}"
        end

        # Create the AutomationCode record
        automation = AutomationCode.create!(
          entity: entity,
          created_by: user,
          name: name,
          description: description.presence || build_automation_description(action, trigger_type, integration),
          trigger_type: trigger_type,
          trigger_config: trigger_config_hash,
          code: code,
          status: "active",
          is_tested: true,  # Template-generated code is pre-tested
          is_compiled: true
        )

        Rails.logger.info "[V3::PlatformCreate] Automation created: #{automation.name} (ID: #{automation.id})"

        @context[:canvas_suggestion] = "automation_dashboard"

        trigger_desc = integration_trigger ? "#{integration} #{trigger}" : trigger_type.humanize.downcase
        success_response(
          automation_id: automation.id,
          name: name,
          trigger: trigger_type,
          integration: integration,
          action: action,
          status: "active",
          message: "Automation '#{name}' is active! It will #{action.humanize.downcase} when #{trigger_desc}.",
          canvas_type: "automation_dashboard"
        )
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Automation build failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        error_response("Automation creation failed: #{e.message}")
      end

      def build_automation_description(action, trigger_type, integration = nil)
        prefix = integration ? "#{integration.titleize}: " : ""
        "#{prefix}#{action.humanize} when #{trigger_type.humanize.downcase}"
      end

      def infer_source_from_trigger(trigger)
        case trigger.to_s
        when /customer/ then "customers"
        when /order/ then "orders"
        when /invoice/ then "invoices"
        when /contact/ then "contacts"
        when /deal/ then "deals"
        else "customers"
        end
      end

      # ═══════════════════════════════════════════════════════════════
      # INTEGRATION — Connect to external APIs
      # ═══════════════════════════════════════════════════════════════

      def build_integration(data)
        name = data["name"] || data[:name]
        base_url = data["base_url"] || data[:base_url]
        documentation_url = data["documentation_url"] || data[:documentation_url] || data["docs_url"] || data[:docs_url]
        auth_type = data["auth_type"] || data[:auth_type]
        category = data["category"] || data[:category]
        description = data["description"] || data[:description]
        api_version = data["api_version"] || data[:api_version]
        test_endpoint = data["test_endpoint"] || data[:test_endpoint]
        auth_configs = data["auth_configs"] || data[:auth_configs]
        auth_placement = data["auth_placement"] || data[:auth_placement]
        auth_header_name = data["auth_header_name"] || data[:auth_header_name]
        operations = data["operations"] || data[:operations]

        # OAuth-specific
        authorize_url = data["authorize_url"] || data[:authorize_url]
        token_url = data["token_url"] || data[:token_url]
        scopes = data["scopes"] || data[:scopes]

        return error_response("Missing: name") if name.blank?
        return error_response("Missing: base_url (the API base URL, e.g., 'https://api.stripe.com/v1')") if base_url.blank?
        return error_response("Missing: documentation_url (URL to the API docs)") if documentation_url.blank?

        Rails.logger.info "[V3::PlatformCreate] Building integration: #{name}"
        stream_progress("Setting up #{name} integration...", percentage: 0)

        factory = Factories::IntegrationFactory.new(user: user, entity: entity)

        # ─── STAGE 1: Create foundation ───
        stream_progress("Creating #{name} foundation...", percentage: 10)

        foundation_result = factory.create_foundation(
          name: name,
          base_url: base_url,
          documentation_url: documentation_url,
          description: description,
          category: category,
          api_version: api_version
        )

        unless foundation_result[:success]
          return error_response(
            "Integration foundation failed: #{factory.errors.join(', ')}",
            hint: "Check that the name is unique and the base_url is a valid public URL."
          )
        end

        integration = foundation_result[:integration]
        integration_id = integration.id

        # ─── STAGE 2: Configure auth (if auth_type provided) ───
        if auth_type.present?
          stream_progress("Configuring #{auth_type} authentication...", percentage: 30)

          auth_result = factory.configure_auth(
            integration_id: integration_id,
            auth_type: auth_type,
            auth_placement: auth_placement,
            test_endpoint: test_endpoint,
            auth_configs: auth_configs,
            auth_header_name: auth_header_name,
            authorize_url: authorize_url,
            token_url: token_url,
            scopes: scopes
          )

          unless auth_result[:success]
            return error_response(
              "Auth configuration failed: #{factory.errors.join(', ')}",
              integration_id: integration_id,
              hint: "Integration was created but auth setup failed. You can retry with platform_execute(action: 'configure_integration_auth', ...)."
            )
          end
        end

        # ─── STAGE 3: Add operations (if provided) ───
        operations_created = []
        if operations.present? && operations.is_a?(Array) && operations.any?
          stream_progress("Adding #{operations.length} API operations...", percentage: 60)

          ops_result = factory.add_operations(
            integration_id: integration_id,
            operations: operations
          )

          if ops_result[:success]
            operations_created = ops_result[:operations_created] || []

            # Auto-generate IntegrationActions for each operation
            stream_progress("Generating action mappings...", percentage: 80)
            operations_created.each do |op|
              begin
                Integrations::ActionGeneratorService.generate_for_operation(op, use_ai: true, entity_id: entity.id, user_id: user.id)
              rescue => e
                Rails.logger.warn "[V3::PlatformCreate] Action generation for #{op.name} failed (non-fatal): #{e.message}"
              end
            end
          else
            Rails.logger.warn "[V3::PlatformCreate] Operations creation had errors: #{factory.errors.join(', ')}"
          end
        end

        stream_progress("#{name} integration ready!", percentage: 100)

        # Build the response
        needs_credentials = auth_type.present? && auth_type != "no_auth"
        credential_message = if needs_credentials
          "Open the Integrations panel to enter your #{auth_type_label(auth_type)}."
        else
          "No authentication needed — you're all set!"
        end

        @context[:canvas_suggestion] = "integrations_manager"

        success_response(
          integration_id: integration_id,
          name: name,
          slug: integration.slug,
          base_url: base_url,
          auth_type: auth_type || "pending",
          operations_count: operations_created.length,
          operations: operations_created.map { |op| { id: op.id, name: op.name, method: op.http_method, path: op.path_template } },
          needs_credentials: needs_credentials,
          message: "#{name} integration created! #{credential_message}",
          canvas_type: "integrations_manager",
          canvas_data: { integration_id: integration_id }
        )
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Integration build failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Integration creation failed: #{e.message}")
      end

      def auth_type_label(auth_type)
        case auth_type.to_s
        when "api_key" then "API key"
        when "bearer_token" then "access token"
        when "basic_auth" then "username and password (or API key)"
        when "oauth2" then "OAuth credentials (client ID and secret)"
        else "credentials"
        end
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

        # Create a ScheduledAgentTask if this is a scheduled sync
        if sync_config.schedule_type == "scheduled" && sync_config.cron_expression.present?
          begin
            sync_config.create_scheduled_task!(user: user)
            Rails.logger.info "[V3::PlatformCreate] Scheduled task created for sync #{sync_config.id}"
          rescue => e
            Rails.logger.warn "[V3::PlatformCreate] Scheduled task creation failed (non-fatal): #{e.message}"
          end
        end

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

      # ═══════════════════════════════════════════════════════════════
      # CUSTOM DOMAIN — Register a custom domain for landing pages, websites, emails
      # ═══════════════════════════════════════════════════════════════

      def build_custom_domain(data)
        domain_name = data["domain_name"] || data[:domain_name] || data["domain"] || data[:domain]
        subdomain = data["subdomain"] || data[:subdomain]
        connection_id = data["connection_id"] || data[:connection_id]

        return error_response("Missing: domain_name (e.g., 'example.com')") if domain_name.blank?

        # Find GoDaddy connection if specified
        connection = nil
        if connection_id.present?
          connection = entity.connections.find_by(id: connection_id)
        end

        service = CustomDomainService.new(entity: entity, user: user)
        result = service.register_domain(domain_name, subdomain: subdomain, connection: connection)

        if result[:success]
          domain = result[:custom_domain]

          success_response(
            custom_domain_id: domain.id,
            domain_name: domain.domain_name,
            full_domain: domain.full_domain,
            cname_target: domain.cname_target,
            web_status: domain.web_status,
            instructions: result[:instructions],
            message: "Domain '#{domain.full_domain}' registered! " \
                     "Point a CNAME record to #{domain.cname_target} to connect it.",
            canvas_type: "custom_domains"
          )
        else
          error_response(result[:error] || result[:errors]&.join(", ") || "Domain registration failed")
        end
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Custom domain creation failed: #{e.message}"
        error_response("Custom domain creation failed: #{e.message}")
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
        trigger_str = trigger.to_s.downcase
        
        # Check for integration-style triggers first (e.g., "stripe.customer_created")
        if trigger_str.include?('.') && AutomationActionRegistry.resolve_integration_trigger(trigger_str)
          return "webhook"
        end
        
        case trigger_str
        when /contact.*created/, /new.*contact/, "contact_created", "record_created" then "record_created"
        when /form.*submit/, "form_submitted", "form_submit" then "form_submit"
        when /status.*change/, "status_changed" then "status_changed"
        when /field.*change/, "field_changed" then "field_changed"
        when /schedule/, /cron/, /daily/, /weekly/, "scheduled" then "schedule"
        when /webhook/ then "webhook"
        when /record.*update/, "record_updated" then "record_updated"
        when /stripe|hubspot|shopify|quickbooks/ then "webhook"  # Integration triggers → webhook
        else "manual"
        end
      end

      # ═══════════════════════════════════════════════════════════════
      # DYNAMIC MODULE RECORDS — CRUD for user-built app data
      # ═══════════════════════════════════════════════════════════════

      def find_and_create_module_record(type, data)
        # Try to find a dynamic module model matching this type
        # Supports: "task", "project_management_task", "project_management/Task", etc.
        model_class = resolve_dynamic_model(type)
        return nil unless model_class

        Rails.logger.info "[V3::PlatformCreate] Creating dynamic module record: #{type}"

        # Filter data to only include valid columns
        valid_columns = model_class.column_names - %w[id created_at updated_at]
        record_data = data.select { |k, _| valid_columns.include?(k.to_s) }
        record_data['entity_id'] = entity.id

        record = model_class.create!(record_data)

        success_response(
          id: record.id,
          type: type,
          record: record.attributes.except('entity_id'),
          message: "Created #{type.titleize} record ##{record.id}"
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("Validation failed: #{e.message}")
      rescue => e
        Rails.logger.error "[V3::PlatformCreate] Dynamic module create failed: #{e.message}"
        error_response("Failed to create #{type}: #{e.message}")
      end

      def resolve_dynamic_model(type)
        return nil unless entity

        # Strategy 1: Check if type matches "module_slug/ModelName" format
        if type.include?('/')
          parts = type.split('/')
          app_module = entity.app_modules.active.find_by(slug: parts[0])
          return nil unless app_module
          return Modules::DynamicModelLoader.instance.get_model(app_module, parts[1].classify)
        end

        # Strategy 2: Direct slug match (e.g., "project_management")
        app_module = entity.app_modules.active.find_by(slug: type)
        if app_module
          model_class = Modules::DynamicModelLoader.instance.get_model(app_module, app_module.slug.classify)
          return model_class if model_class
        end

        # Strategy 3: Check if type matches a sub-module slug (e.g., "project_management_task")
        entity.app_modules.active.each do |mod|
          mod.module_codes.where(code_type: 'model').each do |model_code|
            model_name = model_code.name
            # Match by model name (case-insensitive)
            if model_name.underscore == type || model_name.underscore.pluralize == type
              return Modules::DynamicModelLoader.instance.get_model(mod, model_name)
            end
            # Match by table name
            table = model_code.schema_definition&.dig('table_name')
            if table == type.pluralize || table == type
              return Modules::DynamicModelLoader.instance.get_model(mod, model_name)
            end
          end
        end

        nil
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
          existing_plan = find_existing_plan(name)

          if existing_plan&.status == "completed"
            return return_completed_plan(existing_plan, name)
          end

          if existing_plan&.status == "building"
            return success_response(
              app_id: existing_plan.id,
              name: name,
              message: "App '#{name}' is currently being built. Please wait for it to finish.",
              in_progress: true
            )
          end

          plan = if existing_plan
            Rails.logger.info "[V3::PlatformCreate] Resuming existing plan #{existing_plan.id} (status: #{existing_plan.status}) for '#{name}'"
            stream_progress("Resuming previous build for '#{name}'...", percentage: 5)
            existing_plan.update!(status: "approved") if existing_plan.status.in?(%w[failed paused])
            existing_plan
          else
            planner = ApplicationPlannerService.new(entity: entity, user: user)
            new_plan = planner.create_plan(
              name: name,
              description: description,
              requirements: data.except("name", "description", :name, :description)
            )
            new_plan.update!(status: "approved")
            new_plan
          end

          stream_progress("Building app '#{name}'...", percentage: 10)

          build_progress = ->(msg, pct = nil) { stream_progress(msg, percentage: pct) }

          build_start_time = Time.current
          cancel_check = build_cancellation_check(build_start_time)

          builder = ApplicationBuildService.new(
            plan,
            progress_callback: build_progress,
            cancellation_check: cancel_check
          )
          result = builder.execute!

          if result[:success] == true
            stream_progress("App '#{name}' is ready!", percentage: 100)

            modules = plan.reload.app_modules.where(status: "active")
            built_module = modules.first
            canvas_data = built_module ? { app_module_id: built_module.id } : {}
            module_list = modules.map { |m| "#{m.name} (#{m.slug})" }.join(", ")

            success_response(
              app_id: plan.id,
              name: name,
              modules: modules.map { |m| { id: m.id, name: m.name, slug: m.slug, status: m.status } },
              workflows: result[:results][:workflows]&.length || 0,
              message: "App '#{name}' is built and active with #{modules.count} module(s): #{module_list}. " \
                       "All modules have database tables, CRUD operations, and UI canvases ready. " \
                       "To add data, use platform_create(type: 'module_slug', data: {...}). " \
                       "The app is complete — present the result to the user.",
              canvas_type: built_module ? "module_manager" : nil,
              canvas_data: canvas_data
            )
          elsif result[:success] == :partial
            completed = result[:results][:modules]&.map { |m| m[:name] } || []
            built_module = plan.reload.app_modules.where(status: 'active').first

            success_response(
              app_id: plan.id,
              name: name,
              modules: result[:results][:modules]&.map { |m| { id: m[:id], name: m[:name], slug: m[:slug] } } || [],
              message: "Build paused. Completed so far: #{completed.join(', ')}. All completed modules are active and usable. Ask me to resume anytime.",
              partial: true,
              canvas_type: built_module ? "module_manager" : nil,
              canvas_data: built_module ? { app_module_id: built_module.id } : {}
            )
          else
            error_response("App build failed: #{result[:error]}")
          end
        rescue => e
          Rails.logger.error "[V3::PlatformCreate] App build failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          error_response("App creation failed: #{e.message}")
        end
      end

      def find_existing_plan(name)
        ApplicationPlan.where(entity_id: entity.id)
          .where(status: %w[completed paused building failed approved drafting])
          .where("created_at > ?", 30.days.ago)
          .order(created_at: :desc)
          .detect { |p| p.name.downcase.strip == name.downcase.strip }
      end

      def return_completed_plan(plan, name)
        modules = plan.app_modules.where(status: "active")
        built_module = modules.first

        success_response(
          app_id: plan.id,
          name: name,
          modules: modules.map { |m| { id: m.id, name: m.name, slug: m.slug } },
          message: "App '#{name}' already exists and is active with #{modules.count} module(s): #{modules.map(&:name).join(', ')}. You can use it now or ask me to modify it.",
          canvas_type: built_module ? "module_manager" : nil,
          canvas_data: built_module ? { app_module_id: built_module.id } : {}
        )
      end

      def build_cancellation_check(build_start_time)
        encouragement = %w[yes yeah yep sure ok okay continue go build proceed do resume keep start]

        -> {
          recent = ScoutMessage.where(
            user_id: user.id,
            entity_id: entity.id,
            role: "user"
          ).where("created_at > ?", build_start_time).order(created_at: :desc).first

          return false unless recent

          normalized = recent.content.to_s.downcase.gsub(/[^a-z0-9\s]/, '').strip
          words = normalized.split

          # Short affirmative messages are encouragement, not cancellation
          return false if words.length <= 4 && words.any? { |w| encouragement.include?(w) }

          true
        }
      end
    end
  end
end
