# frozen_string_literal: true

# AutomationActionRegistry - Deterministic action templates for automations
#
# When Amos creates an automation via platform_create(type: "automation"),
# this registry generates the Ruby code that will run deterministically
# at trigger time. NO AI at runtime.
#
# The AI's job is to select the right action and fill in the config.
# The platform's job is to generate and execute the deterministic code.
#
class AutomationActionRegistry
  # Available actions and their required config
  ACTIONS = {
    "send_email" => {
      description: "Send an email template to the triggering record",
      required_config: %w[template_id],
      optional_config: %w[to_field],
    },
    "add_to_campaign" => {
      description: "Enroll the contact in a drip campaign",
      required_config: %w[campaign_id],
      optional_config: [],
    },
    "update_field" => {
      description: "Update a field on the triggering record",
      required_config: %w[field value],
      optional_config: [],
    },
    "create_activity" => {
      description: "Log a CRM activity on the contact",
      required_config: %w[activity_type subject],
      optional_config: %w[description],
    },
    "call_webhook" => {
      description: "POST data to an external URL",
      required_config: %w[url],
      optional_config: %w[headers],
    },
    "notify_user" => {
      description: "Send a notification to the record owner or a specific user",
      required_config: %w[message],
      optional_config: %w[user_id],
    },
    "create_contact" => {
      description: "Create a contact from integration/webhook data (e.g., Stripe customer → Contact)",
      required_config: %w[field_mappings],
      optional_config: %w[integration source],
    },
    "sync_integration_data" => {
      description: "Pull data from a connected integration and sync to platform records",
      required_config: %w[integration resource_type],
      optional_config: %w[field_mappings target_type],
    },
    "update_module_record" => {
      description: "Update a field on a dynamic module record (any app module type)",
      required_config: %w[module_slug field value],
      optional_config: %w[model_name],
    },
    "create_module_record" => {
      description: "Create a new record in a dynamic module (any app module type)",
      required_config: %w[module_slug field_values],
      optional_config: %w[model_name],
    },
    "notify_on_module_event" => {
      description: "Send a notification when a module record changes status or is created",
      required_config: %w[module_slug message],
      optional_config: %w[user_id event_type],
    }
  }.freeze

  # Integration-aware trigger types that map external events to automations
  INTEGRATION_TRIGGERS = {
    "stripe.customer_created"    => { trigger_type: "webhook", event_filter: "customer.created", integration: "stripe" },
    "stripe.payment_received"    => { trigger_type: "webhook", event_filter: "invoice.payment_succeeded", integration: "stripe" },
    "stripe.subscription_created"=> { trigger_type: "webhook", event_filter: "customer.subscription.created", integration: "stripe" },
    "stripe.charge_succeeded"    => { trigger_type: "webhook", event_filter: "charge.succeeded", integration: "stripe" },
    "hubspot.contact_created"    => { trigger_type: "webhook", event_filter: "contact.creation", integration: "hubspot" },
    "hubspot.deal_created"       => { trigger_type: "webhook", event_filter: "deal.creation", integration: "hubspot" },
    "shopify.order_created"      => { trigger_type: "webhook", event_filter: "orders/create", integration: "shopify" },
    "shopify.customer_created"   => { trigger_type: "webhook", event_filter: "customers/create", integration: "shopify" },
    "quickbooks.customer_created"=> { trigger_type: "webhook", event_filter: "Customer.Create", integration: "quickbooks" },
    "quickbooks.invoice_created" => { trigger_type: "webhook", event_filter: "Invoice.Create", integration: "quickbooks" },
  }.freeze

  # Default field mappings for common integration syncs
  DEFAULT_FIELD_MAPPINGS = {
    ["stripe", "customers"] => {
      "name" => "full_name", "email" => "email", "phone" => "phone",
      "id" => "metadata.stripe_id", "created" => "metadata.stripe_created_at"
    },
    ["hubspot", "contacts"] => {
      "firstname" => "first_name", "lastname" => "last_name",
      "email" => "email", "phone" => "phone", "company" => "metadata.company"
    },
    ["shopify", "customers"] => {
      "first_name" => "first_name", "last_name" => "last_name",
      "email" => "email", "phone" => "phone"
    },
    ["quickbooks", "customers"] => {
      "DisplayName" => "full_name",
      "PrimaryEmailAddr.Address" => "email",
      "PrimaryPhone.FreeFormNumber" => "phone"
    }
  }.freeze

  class << self
    # Generate deterministic Ruby code for an action
    def generate_code(action:, action_config:, trigger:, name:)
      template = ACTIONS[action]
      raise ArgumentError, "Unknown action: #{action}. Available: #{ACTIONS.keys.join(', ')}" unless template

      # Validate required config
      missing = template[:required_config].select { |k| action_config[k].blank? && action_config[k.to_sym].blank? }
      if missing.any?
        raise ArgumentError, "Missing required config for #{action}: #{missing.join(', ')}"
      end

      case action
      when "send_email"
        generate_send_email_code(action_config, name)
      when "add_to_campaign"
        generate_add_to_campaign_code(action_config, name)
      when "update_field"
        generate_update_field_code(action_config, name)
      when "create_activity"
        generate_create_activity_code(action_config, name)
      when "call_webhook"
        generate_call_webhook_code(action_config, name)
      when "notify_user"
        generate_notify_user_code(action_config, name)
      when "create_contact"
        generate_create_contact_code(action_config, name)
      when "sync_integration_data"
        generate_sync_integration_code(action_config, name)
      when "update_module_record"
        generate_update_module_record_code(action_config, name)
      when "create_module_record"
        generate_create_module_record_code(action_config, name)
      when "notify_on_module_event"
        generate_notify_on_module_event_code(action_config, name)
      end
    end

    # Resolve an integration trigger name to trigger config
    # e.g., "stripe.customer_created" → { trigger_type: "webhook", event_filter: "customer.created", integration: "stripe" }
    def resolve_integration_trigger(trigger_name)
      INTEGRATION_TRIGGERS[trigger_name.to_s]
    end

    # Get default field mappings for an integration + resource type
    def default_field_mappings(integration, resource_type)
      DEFAULT_FIELD_MAPPINGS[[integration.to_s, resource_type.to_s]] || {}
    end

    # List available actions for the AI
    def available_actions
      ACTIONS.map do |name, config|
        {
          action: name,
          description: config[:description],
          required_config: config[:required_config],
          optional_config: config[:optional_config]
        }
      end
    end

    # List available integration triggers
    def available_integration_triggers
      INTEGRATION_TRIGGERS.map do |name, config|
        {
          trigger: name,
          integration: config[:integration],
          event_filter: config[:event_filter]
        }
      end
    end

    private

    def generate_send_email_code(config, name)
      template_id = config["template_id"] || config[:template_id]
      to_field = config["to_field"] || config[:to_field] || "email"

      <<~RUBY
        # Automation: #{name}
        # Action: Send email template #{template_id}
        def execute(trigger_data)
          record = trigger_data[:record] || trigger_data["record"] || {}
          record_id = record["id"] || record[:id]
          entity_id = trigger_data[:entity_id] || trigger_data["entity_id"]
          
          contact = Contact.find_by(id: record_id)
          return { success: false, error: "Contact not found" } unless contact
          
          to_email = contact.#{to_field}
          return { success: false, error: "No email address" } if to_email.blank?
          
          template = EmailTemplate.find_by(id: #{template_id})
          return { success: false, error: "Template not found" } unless template
          
          rendered_subject = template.subject.to_s
          rendered_body = template.body.to_s
          
          contact.attributes.each do |key, value|
            next if value.blank?
            rendered_subject = rendered_subject.gsub("\#\{" + key + "\}", value.to_s)
            rendered_body = rendered_body.gsub("\#\{" + key + "\}", value.to_s)
          end
          
          WorkflowMailer.workflow_email(
            to: to_email,
            subject: rendered_subject,
            body: rendered_body,
            html: true,
            entity_id: entity_id,
            automation_id: trigger_data[:automation_id],
            contact_id: contact.id
          ).deliver_later
          
          { success: true, sent_to: to_email, template_id: #{template_id} }
        end
      RUBY
    end

    def generate_add_to_campaign_code(config, name)
      campaign_id = config["campaign_id"] || config[:campaign_id]

      <<~RUBY
        # Automation: #{name}
        # Action: Add to campaign #{campaign_id}
        def execute(trigger_data)
          record = trigger_data[:record] || trigger_data["record"] || {}
          record_id = record["id"] || record[:id]
          entity_id = trigger_data[:entity_id] || trigger_data["entity_id"]
          
          contact = Contact.find_by(id: record_id)
          return { success: false, error: "Contact not found" } unless contact
          
          # Find the sequence/campaign
          sequence = EmailSequence.find_by(id: #{campaign_id}, entity_id: entity_id)
          return { success: false, error: "Campaign not found" } unless sequence
          
          enrollment = SequenceEnrollment.create!(
            email_sequence: sequence,
            contact: contact,
            entity_id: entity_id,
            status: 'pending',
            current_step_number: 0
          )
          
          { success: true, enrollment_id: enrollment.id, campaign_id: #{campaign_id} }
        end
      RUBY
    end

    def generate_update_field_code(config, name)
      field = config["field"] || config[:field]
      value = config["value"] || config[:value]

      <<~RUBY
        # Automation: #{name}
        # Action: Update field #{field}
        def execute(trigger_data)
          record = trigger_data[:record] || trigger_data["record"] || {}
          record_id = record["id"] || record[:id]
          
          contact = Contact.find_by(id: record_id)
          return { success: false, error: "Record not found" } unless contact
          
          contact.update!("#{field}" => "#{value}")
          
          { success: true, field: "#{field}", value: "#{value}" }
        end
      RUBY
    end

    def generate_create_activity_code(config, name)
      activity_type = config["activity_type"] || config[:activity_type]
      subject = config["subject"] || config[:subject]
      description = config["description"] || config[:description] || ""

      <<~RUBY
        # Automation: #{name}
        # Action: Create activity
        def execute(trigger_data)
          record = trigger_data[:record] || trigger_data["record"] || {}
          record_id = record["id"] || record[:id]
          entity_id = trigger_data[:entity_id] || trigger_data["entity_id"]
          
          contact = Contact.find_by(id: record_id)
          
          Activity.create!(
            entity_id: entity_id,
            contact: contact,
            activity_type: "#{activity_type}",
            subject: "#{subject}",
            description: "#{description}",
            status: 'completed',
            completed_at: Time.current,
            metadata: { automation: "#{name}", trigger: trigger_data[:event] }
          )
          
          { success: true, activity_type: "#{activity_type}" }
        end
      RUBY
    end

    def generate_call_webhook_code(config, name)
      url = config["url"] || config[:url]

      <<~RUBY
        # Automation: #{name}
        # Action: Call webhook
        def execute(trigger_data)
          # Use sandbox http_post helper (direct HTTP is blocked in sandbox)
          result = http_post("#{url}", body: trigger_data.to_json, headers: { "Content-Type" => "application/json" })
          
          { success: result[:status].to_i < 400, status_code: result[:status], body: result[:body].to_s.truncate(500) }
        end
      RUBY
    end

    def generate_notify_user_code(config, name)
      message = config["message"] || config[:message]
      user_id = config["user_id"] || config[:user_id]

      <<~RUBY
        # Automation: #{name}
        # Action: Notify user
        def execute(trigger_data)
          entity_id = trigger_data[:entity_id] || trigger_data["entity_id"]
          
          user = #{user_id ? "User.find_by(id: #{user_id})" : "User.joins(:entity_users).where(entity_users: { entity_id: entity_id, role: ['admin', 'owner'] }).first"}
          return { success: false, error: "No user to notify" } unless user
          
          AgentWorkItem.create!(
            entity_id: entity_id,
            user: user,
            work_type: 'automation_notification',
            title: "Automation: #{name}",
            summary: "#{message}",
            priority: 'normal',
            metadata: { automation: "#{name}" }
          )
          
          { success: true, notified_user_id: user.id }
        end
      RUBY
    end

    def generate_create_contact_code(config, name)
      field_mappings = config["field_mappings"] || config[:field_mappings] || {}
      integration = config["integration"] || config[:integration] || "unknown"
      source = config["source"] || config[:source] || "webhook"

      # Build the field mapping logic as Ruby code
      mapping_lines = field_mappings.map do |source_field, target_field|
        if target_field.start_with?("metadata.")
          meta_key = target_field.sub("metadata.", "")
          "          metadata[\"#{meta_key}\"] = extract_field(payload, \"#{source_field}\")"
        else
          "          attrs[\"#{target_field}\"] = extract_field(payload, \"#{source_field}\")"
        end
      end.join("\n")

      <<~RUBY
        # Automation: #{name}
        # Action: Create contact from #{integration} #{source} data
        def execute(trigger_data)
          entity_id = trigger_data[:entity_id] || trigger_data["entity_id"]
          payload = trigger_data[:payload] || trigger_data["payload"] || trigger_data[:record] || trigger_data["record"] || {}
          
          # Handle nested event data (e.g., Stripe wraps in data.object)
          payload = payload["data"]["object"] if payload.is_a?(Hash) && payload.dig("data", "object")
          
          attrs = {}
          metadata = {}
          
#{mapping_lines}
          
          # Skip if no email found
          return { success: false, error: "No email in payload" } if attrs["email"].blank?
          
          # Upsert: find existing contact by email or create new
          contact = Contact.find_or_initialize_by(entity_id: entity_id, email: attrs["email"])
          was_new = contact.new_record?
          
          attrs.each do |key, value|
            contact.send(:"#\{key\}=", value) if contact.respond_to?(:"#\{key\}=") && value.present?
          end
          
          contact.lifecycle_stage ||= "lead"
          contact.status ||= "active"
          contact.source ||= "#{integration}"
          contact.metadata = (contact.metadata || {}).merge(metadata).merge(
            "synced_from" => "#{integration}",
            "synced_at" => Time.current.iso8601
          )
          
          contact.save!
          
          { success: true, contact_id: contact.id, email: contact.email, created: was_new, source: "#{integration}" }
        end
        
        def extract_field(data, field_path)
          parts = field_path.to_s.split(".")
          result = data
          parts.each { |p| result = result.is_a?(Hash) ? (result[p] || result[p.to_sym]) : nil }
          result
        end
      RUBY
    end

    def generate_update_module_record_code(config, name)
      module_slug = config["module_slug"] || config[:module_slug]
      field = config["field"] || config[:field]
      value = config["value"] || config[:value]
      model_name = config["model_name"] || config[:model_name] || module_slug.classify

      <<~RUBY
        # Automation: #{name}
        # Action: Update field on dynamic module record (#{module_slug})
        def execute(trigger_data)
          record = trigger_data[:record] || trigger_data["record"] || {}
          record_id = record["id"] || record[:id]
          entity_id = trigger_data[:entity_id] || trigger_data["entity_id"]
          
          # Load the dynamic module model
          app_module = AppModule.find_by(slug: "#{module_slug}", entity_id: entity_id)
          return { success: false, error: "Module '#{module_slug}' not found" } unless app_module
          
          model_class = Modules::DynamicModelLoader.instance.get_model(app_module, "#{model_name}")
          return { success: false, error: "Model class not loaded" } unless model_class
          
          target = model_class.find_by(id: record_id, entity_id: entity_id)
          return { success: false, error: "Record not found" } unless target
          
          target.update!("#{field}" => "#{value}")
          
          { success: true, record_id: target.id, field: "#{field}", value: "#{value}" }
        rescue => e
          { success: false, error: e.message }
        end
      RUBY
    end

    def generate_create_module_record_code(config, name)
      module_slug = config["module_slug"] || config[:module_slug]
      field_values = config["field_values"] || config[:field_values] || {}
      model_name = config["model_name"] || config[:model_name] || module_slug.classify
      values_json = field_values.to_json

      <<~RUBY
        # Automation: #{name}
        # Action: Create new record in dynamic module (#{module_slug})
        def execute(trigger_data)
          entity_id = trigger_data[:entity_id] || trigger_data["entity_id"]
          payload = trigger_data[:payload] || trigger_data["payload"] || trigger_data[:record] || {}
          
          app_module = AppModule.find_by(slug: "#{module_slug}", entity_id: entity_id)
          return { success: false, error: "Module '#{module_slug}' not found" } unless app_module
          
          model_class = Modules::DynamicModelLoader.instance.get_model(app_module, "#{model_name}")
          return { success: false, error: "Model class not loaded" } unless model_class
          
          # Merge predefined field values with any trigger payload data
          attrs = JSON.parse('#{values_json}')
          
          # Allow trigger payload to override/supplement field values
          payload.each do |key, value|
            attrs[key.to_s] = value if model_class.column_names.include?(key.to_s)
          end
          
          attrs["entity_id"] = entity_id
          
          record = model_class.create!(attrs)
          
          { success: true, record_id: record.id, module: "#{module_slug}" }
        rescue => e
          { success: false, error: e.message }
        end
      RUBY
    end

    def generate_notify_on_module_event_code(config, name)
      module_slug = config["module_slug"] || config[:module_slug]
      message = config["message"] || config[:message]
      user_id = config["user_id"] || config[:user_id]
      event_type = config["event_type"] || config[:event_type] || "module_event"

      <<~RUBY
        # Automation: #{name}
        # Action: Notify on module event (#{module_slug})
        def execute(trigger_data)
          entity_id = trigger_data[:entity_id] || trigger_data["entity_id"]
          record = trigger_data[:record] || trigger_data["record"] || {}
          event = trigger_data[:event] || trigger_data["event"] || "#{event_type}"
          
          user = #{user_id ? "User.find_by(id: #{user_id})" : "User.joins(:entity_users).where(entity_users: { entity_id: entity_id, role: ['admin', 'owner'] }).first"}
          return { success: false, error: "No user to notify" } unless user
          
          # Interpolate record data into message
          message = "#{message}"
          record.each do |key, value|
            message = message.gsub("\\\#{" + key.to_s + "}", value.to_s)
          end if record.is_a?(Hash)
          
          AgentWorkItem.create!(
            entity_id: entity_id,
            user: user,
            work_type: 'automation_notification',
            title: "#{module_slug.titleize}: " + event.to_s.humanize,
            summary: message,
            priority: 'normal',
            metadata: { automation: "#{name}", module: "#{module_slug}", event: event }
          )
          
          { success: true, notified_user_id: user.id, module: "#{module_slug}" }
        end
      RUBY
    end

    def generate_sync_integration_code(config, name)
      integration = config["integration"] || config[:integration]
      resource_type = config["resource_type"] || config[:resource_type]
      target_type = config["target_type"] || config[:target_type] || "Contact"
      field_mappings = config["field_mappings"] || config[:field_mappings] || {}

      # Use default mappings if none provided
      if field_mappings.empty?
        defaults = DEFAULT_FIELD_MAPPINGS[[integration.to_s, resource_type.to_s]]
        field_mappings = defaults if defaults
      end

      mapping_json = field_mappings.to_json

      <<~RUBY
        # Automation: #{name}
        # Action: Sync #{integration} #{resource_type} → #{target_type}
        def execute(trigger_data)
          entity_id = trigger_data[:entity_id] || trigger_data["entity_id"]
          
          # Find the integration connection
          connection = Connection.joins(:integration)
            .where(integrations: { slug: "#{integration}" }, entity_id: entity_id)
            .where.not(status: :disconnected)
            .first
          
          return { success: false, error: "No active #{integration} connection" } unless connection
          
          # Execute the sync via IntegrationSyncService
          field_mappings = JSON.parse('#{mapping_json}')
          
          sync_config = IntegrationSyncConfig.find_or_create_by!(
            entity_id: entity_id,
            connection: connection,
            resource_type: "#{resource_type}",
            target_type: "#{target_type}"
          ) do |config|
            config.field_mappings = field_mappings
            config.sync_direction = "inbound"
            config.sync_mode = "incremental"
            config.conflict_resolution = "external_wins"
            config.schedule_type = "manual"
            config.enabled = true
          end
          
          result = sync_config.execute_sync!(user: nil)
          
          { success: true, sync_id: sync_config.id, records_synced: result[:records_synced] || 0 }
        rescue => e
          { success: false, error: e.message }
        end
      RUBY
    end
  end
end
