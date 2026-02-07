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
      end
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
  end
end
