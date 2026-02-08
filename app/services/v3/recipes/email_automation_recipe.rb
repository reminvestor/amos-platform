# frozen_string_literal: true

module V3
  module Recipes
    # EmailAutomationRecipe - Create email templates + automations in one step
    #
    # Handles compound goals like "welcome email automation" which require
    # both an email template AND an automation wired together.
    # Also handles standalone email template creation and automation creation.
    #
    class EmailAutomationRecipe < Base
      EMAIL_AUTO_PATTERNS = [
        /welcome\s*email\s*(auto|flow|sequence|trigger)/,
        /email\s*(auto|flow|sequence|trigger).*welcome/,
        /auto.*welcome.*email/,
        /onboarding\s*email/,
        /set\s*up\s*(a\s+)?.*email.*(auto|flow|trigger|when)/,
        /send\s*(a\s+)?.*email\s*when/,
        /email\s*on\s*(new|form|contact|lead)/,
      ].freeze

      EMAIL_TEMPLATE_PATTERNS = [
        /\bcreate\s*(a\s+)?email\s*template/,
        /\bnew\s+email\s*template/,
        /\bcreate\s*(a\s+)?template/,
      ].freeze

      AUTOMATION_PATTERNS = [
        /\bcreate\s*(a\s+)?automation/,
        /\bnew\s+automation/,
        /\bset\s*up\s*(a\s+)?automation/,
        /\bcreate\s*(a\s+)?workflow/,
        /\bwhen\s+.*\s+then\s+/,
      ].freeze

      def self.matches?(goal, spec = {})
        EMAIL_AUTO_PATTERNS.any? { |p| goal.match?(p) } ||
          EMAIL_TEMPLATE_PATTERNS.any? { |p| goal.match?(p) } ||
          AUTOMATION_PATTERNS.any? { |p| goal.match?(p) }
      end

      def self.priority
        15 # Higher than contact (more specific)
      end

      def execute(spec:)
        goal_lower = (context[:original_goal] || "").downcase

        if EMAIL_AUTO_PATTERNS.any? { |p| goal_lower.match?(p) }
          create_email_automation(spec)
        elsif EMAIL_TEMPLATE_PATTERNS.any? { |p| goal_lower.match?(p) }
          create_email_template(spec)
        else
          create_automation(spec)
        end
      end

      private

      # Compound: create email template + wire automation
      def create_email_automation(spec)
        stream_progress("Creating email template...", percentage: 20)

        # Step 1: Create the email template
        template_name = spec_val(spec, :template_name) || spec_val(spec, :name) || "Welcome Email"
        subject = spec_val(spec, :subject) || spec_val(spec, :email_subject) || "Welcome!"
        body = spec_val(spec, :body) || spec_val(spec, :email_body) || "<h1>Welcome!</h1><p>Thanks for joining us.</p>"

        template_result = platform_create(
          type: "email_template",
          data: { name: template_name, subject: subject, body: body }
        )

        unless template_result.is_a?(Hash) && template_result[:success] != false
          return error_response("Failed to create email template: #{template_result[:error]}")
        end

        template_id = template_result[:id] || template_result[:email_template_id]

        stream_progress("Creating automation trigger...", percentage: 60)

        # Step 2: Create the automation wired to the template
        trigger = spec_val(spec, :trigger) || "contact_created"
        automation_name = spec_val(spec, :automation_name) || "#{template_name} Automation"

        automation_result = platform_create(
          type: "automation",
          data: {
            name: automation_name,
            trigger: normalize_trigger(trigger),
            action: "send_email",
            action_config: { template_id: template_id }
          }
        )

        unless automation_result.is_a?(Hash) && automation_result[:success] != false
          return error_response(
            "Email template created (ID: #{template_id}), but automation failed: #{automation_result[:error]}"
          )
        end

        stream_progress("Done!", percentage: 100)

        success_response(
          email_template: {
            id: template_id,
            name: template_name,
            subject: subject
          },
          automation: {
            id: automation_result[:automation_id],
            name: automation_name,
            trigger: trigger
          },
          created: [
            { type: "email_template", id: template_id, name: template_name },
            { type: "automation", id: automation_result[:automation_id], name: automation_name }
          ],
          message: "Created '#{template_name}' template and wired it to fire on #{trigger}.",
          canvas_type: "automation_dashboard"
        )
      end

      # Standalone email template creation
      def create_email_template(spec)
        data = {
          name: spec_val(spec, :name) || "Email Template",
          subject: spec_val(spec, :subject) || "",
          body: spec_val(spec, :body) || ""
        }
        # Pass through any additional fields
        data.merge!(spec_val(spec, :data, {}))
        platform_create(type: "email_template", data: data)
      end

      # Standalone automation creation
      def create_automation(spec)
        platform_create(
          type: "automation",
          data: {
            name: spec_val(spec, :name) || "Automation",
            trigger: spec_val(spec, :trigger) || "",
            action: spec_val(spec, :action) || "",
            action_config: spec_val(spec, :action_config, {}),
            description: spec_val(spec, :description)
          }.compact
        )
      end

      def normalize_trigger(trigger)
        case trigger.to_s.downcase
        when /new.?lead/, /new.?contact/, /contact.?created/ then "contact_created"
        when /form/, /submit/ then "form_submit"
        when /status/ then "status_changed"
        when /field/ then "field_changed"
        when /schedule/, /cron/ then "schedule"
        when /webhook/ then "webhook"
        else trigger.to_s
        end
      end
    end
  end
end
