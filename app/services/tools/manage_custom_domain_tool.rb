# frozen_string_literal: true

module Tools
  # ManageCustomDomainTool - Platform-automated DNS setup for custom domains
  #
  # This tool handles the deterministic DNS setup flows that users wouldn't
  # understand (CNAME, DKIM, SPF, DMARC, MX records). For general GoDaddy
  # operations (list domains, check DNS, etc.), the AI uses
  # execute_integration_action like any other integration.
  #
  # The tool is a thin wrapper -- all orchestration happens in
  # CustomDomainService and SesDomainService.
  #
  class ManageCustomDomainTool < BaseTool
    def self.metadata
      {
        name: "manage_custom_domain",
        description: <<~DESC.strip,
          Set up and manage custom domains for web publishing (landing pages, apps, websites)
          and email sending. The platform handles all DNS configuration automatically.

          **Actions:**
          - `setup_web` -- Register a domain for web publishing. Auto-configures CNAME via GoDaddy if connected.
          - `setup_email` -- Set up email sending (SES). Auto-configures DKIM/SPF/DMARC via GoDaddy if connected.
          - `check_status` -- Check verification status of a domain (web, email, SSL).
          - `list` -- List all custom domains for this entity.

          **Note:** For general GoDaddy operations (list domains, check DNS records, etc.),
          use `execute_integration_action(integration: "godaddy", ...)` instead.
        DESC
        category: "platform",
        input_schema: {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: %w[setup_web setup_email check_status list],
              description: "The action to perform"
            },
            domain_name: {
              type: "string",
              description: "Domain name (e.g., 'example.com'). Required for setup_web."
            },
            subdomain: {
              type: "string",
              description: "Optional subdomain (e.g., 'app' for app.example.com). Used with setup_web."
            },
            domain_id: {
              type: "integer",
              description: "Custom domain record ID. Required for setup_email and check_status."
            }
          },
          required: %w[action]
        }
      }
    end

    def execute(args)
      log_execution(args)

      action = get_arg(args, :action)

      case action
      when "setup_web"
        setup_web(args)
      when "setup_email"
        setup_email(args)
      when "check_status"
        check_status(args)
      when "list"
        list_domains
      else
        error_response("Unknown action: #{action}", valid_actions: %w[setup_web setup_email check_status list])
      end
    end

    private

    # =========================================
    # setup_web -- Register domain + auto-configure CNAME
    # =========================================

    def setup_web(args)
      domain_name = get_arg(args, :domain_name)
      subdomain = get_arg(args, :subdomain)

      return error_response("domain_name is required for setup_web") unless domain_name.present?

      # Check if domain already exists
      existing = entity.custom_domains.find_by(domain_name: domain_name.downcase)
      if existing
        return success_response(
          domain_id: existing.id,
          domain_name: existing.full_domain,
          cname_target: existing.cname_target,
          web_status: existing.web_status,
          ssl_status: existing.ssl_status,
          message: "Domain #{existing.full_domain} already registered.",
          already_existed: true
        )
      end

      # Find GoDaddy connection if available (for auto-DNS)
      godaddy_connection = find_godaddy_connection

      # Register the domain via CustomDomainService
      service = CustomDomainService.new(entity: entity, user: user)
      result = service.register_domain(domain_name, subdomain: subdomain, connection: godaddy_connection)

      if result[:success]
        custom_domain = result[:custom_domain]

        response_data = {
          domain_id: custom_domain.id,
          domain_name: custom_domain.full_domain,
          cname_target: custom_domain.cname_target,
          web_status: custom_domain.web_status,
          auto_dns: godaddy_connection.present?,
          message: build_setup_web_message(custom_domain, godaddy_connection)
        }

        # If GoDaddy connected, DNS is being configured automatically
        if godaddy_connection.present?
          response_data[:dns_auto_configured] = true
          response_data[:verification_scheduled] = true
        else
          # Manual setup -- provide instructions
          response_data[:dns_instructions] = result[:instructions]
        end

        # Suggest loading the custom domains canvas
        @context[:canvas_suggestion] = "custom_domains"

        success_response(response_data)
      else
        error_response(result[:error] || result[:errors]&.join(", ") || "Failed to register domain")
      end
    end

    # =========================================
    # setup_email -- Start SES verification + auto-configure email DNS
    # =========================================

    def setup_email(args)
      domain_id = get_arg(args, :domain_id)
      domain_name = get_arg(args, :domain_name)

      # Find the custom domain
      custom_domain = find_custom_domain(domain_id, domain_name)
      return error_response("Custom domain not found. Use setup_web first to register the domain.") unless custom_domain

      # Check if email is already verified
      if custom_domain.email_verified?
        return success_response(
          domain_id: custom_domain.id,
          domain_name: custom_domain.full_domain,
          email_status: "verified",
          message: "Email sending is already verified for #{custom_domain.domain_name}."
        )
      end

      # Start SES verification -- platform handles everything
      ses_service = SesDomainService.new(custom_domain: custom_domain)
      result = ses_service.start_verification

      if result[:success]
        response_data = {
          domain_id: custom_domain.id,
          domain_name: custom_domain.full_domain,
          email_status: custom_domain.reload.email_status,
          auto_dns: custom_domain.can_auto_configure?,
          message: build_setup_email_message(custom_domain)
        }

        if custom_domain.can_auto_configure?
          response_data[:dns_auto_configured] = true
          response_data[:verification_scheduled] = true
        else
          response_data[:dns_instructions] = result[:instructions]
        end

        @context[:canvas_suggestion] = "custom_domains"

        success_response(response_data)
      else
        error_response(result[:error] || "Failed to start email verification")
      end
    end

    # =========================================
    # check_status -- Return full domain status
    # =========================================

    def check_status(args)
      domain_id = get_arg(args, :domain_id)
      domain_name = get_arg(args, :domain_name)

      custom_domain = find_custom_domain(domain_id, domain_name)
      return error_response("Custom domain not found") unless custom_domain

      response_data = {
        domain_id: custom_domain.id,
        domain_name: custom_domain.full_domain,
        cname_target: custom_domain.cname_target,
        web_status: custom_domain.web_status,
        email_status: custom_domain.email_status,
        ssl_status: custom_domain.ssl_status,
        is_primary: custom_domain.is_primary?,
        fully_configured: custom_domain.fully_configured?,
        ready_for_email: custom_domain.ready_for_email?,
        auto_dns_configured: custom_domain.auto_dns_configured?,
        has_godaddy_connection: custom_domain.can_auto_configure?
      }

      # Add URLs if fully configured
      if custom_domain.fully_configured?
        response_data[:base_url] = custom_domain.base_url
      end

      # Add last error if any
      response_data[:last_error] = custom_domain.last_error if custom_domain.last_error.present?

      # Add connected assets
      response_data[:landing_pages] = custom_domain.landing_pages.count
      response_data[:websites] = custom_domain.websites.count

      @context[:canvas_suggestion] = "custom_domains"

      success_response(response_data)
    end

    # =========================================
    # list -- List all domains + load canvas
    # =========================================

    def list_domains
      domains = entity.custom_domains.order(created_at: :desc)

      domain_list = domains.map do |d|
        {
          id: d.id,
          domain: d.full_domain,
          web_status: d.web_status,
          email_status: d.email_status,
          ssl_status: d.ssl_status,
          is_primary: d.is_primary?,
          assets: d.landing_pages.count + d.websites.count
        }
      end

      @context[:canvas_suggestion] = "custom_domains"

      success_response(
        domains: domain_list,
        count: domains.count,
        message: domains.any? ? "Found #{domains.count} custom domain(s)." : "No custom domains configured yet."
      )
    end

    # =========================================
    # Helpers
    # =========================================

    def find_custom_domain(domain_id, domain_name)
      if domain_id.present?
        entity.custom_domains.find_by(id: domain_id)
      elsif domain_name.present?
        entity.custom_domains.find_by(domain_name: domain_name.downcase)
      end
    end

    def find_godaddy_connection
      entity.connections
            .active
            .joins(:integration)
            .where(integrations: { slug: 'godaddy' })
            .order(created_at: :desc)
            .first
    end

    def build_setup_web_message(custom_domain, godaddy_connection)
      if godaddy_connection.present?
        "Domain #{custom_domain.full_domain} registered. CNAME record is being configured automatically via GoDaddy. " \
        "Verification will start in ~2 minutes. I'll let you know when it's ready."
      else
        "Domain #{custom_domain.full_domain} registered. Your CNAME target is: #{custom_domain.cname_target}. " \
        "Add a CNAME record pointing #{custom_domain.subdomain.presence || 'your domain'} to #{custom_domain.cname_target} " \
        "in your DNS settings, then I can verify it."
      end
    end

    def build_setup_email_message(custom_domain)
      if custom_domain.can_auto_configure?
        "Email verification started for #{custom_domain.domain_name}. " \
        "DKIM, SPF, and DMARC records are being configured automatically via GoDaddy. " \
        "Verification typically takes 1-2 hours."
      else
        "Email verification started for #{custom_domain.domain_name}. " \
        "Please add the required DNS records (DKIM, SPF, DMARC) shown in the instructions, " \
        "then I can check the verification status."
      end
    end
  end
end
