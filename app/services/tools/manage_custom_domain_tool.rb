# frozen_string_literal: true

module Tools
  # ManageCustomDomainTool - Add, verify, and manage custom domains
  #
  # Allows users to:
  # - Add their own domain for publishing landing pages/websites
  # - Verify DNS configuration
  # - Set up email sending from their domain
  # - Configure auto-DNS via GoDaddy integration
  #
  class ManageCustomDomainTool < BaseTool
    def self.metadata
      {
        name: "manage_custom_domain",
        description: <<~DESC.strip,
          Manage custom domains for publishing landing pages, websites, and sending emails.
          
          Actions:
          - "add": Register a new custom domain
          - "list": Show all custom domains for the entity
          - "verify_web": Check if CNAME record is configured
          - "verify_email": Check if email DNS records are configured
          - "start_email_setup": Begin email verification process
          - "set_primary": Set a domain as the primary domain
          - "delete": Remove a custom domain
          
          When adding a domain, the system will:
          1. Generate a unique CNAME target (e.g., abc123.custom.amoslabs.co)
          2. Show the user the DNS records to add
          3. If GoDaddy is connected, auto-configure DNS
          4. Provision SSL certificate once verified
        DESC
        category: "domain_management",
        input_schema: {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: %w[add list verify_web verify_email start_email_setup set_primary delete],
              description: "The action to perform"
            },
            domain_name: {
              type: "string",
              description: "Domain name (e.g., 'example.com') - required for add"
            },
            subdomain: {
              type: "string",
              description: "Subdomain to use (e.g., 'app' for app.example.com). Leave empty for root domain."
            },
            domain_id: {
              type: "integer",
              description: "ID of existing custom domain - required for verify, set_primary, delete"
            },
            use_godaddy: {
              type: "boolean",
              description: "If true and GoDaddy is connected, auto-configure DNS"
            }
          },
          required: ["action"]
        }
      }
    end

    def execute(args)
      action = get_arg(args, :action)
      
      case action
      when "add"
        add_domain(args)
      when "list"
        list_domains
      when "verify_web"
        verify_web(args)
      when "verify_email"
        verify_email(args)
      when "start_email_setup"
        start_email_setup(args)
      when "set_primary"
        set_primary(args)
      when "delete"
        delete_domain(args)
      else
        error_response("Unknown action: #{action}")
      end
    end

    private

    # =========================================
    # ADD DOMAIN
    # =========================================

    def add_domain(args)
      domain_name = get_arg(args, :domain_name)
      subdomain = get_arg(args, :subdomain)
      use_godaddy = get_arg(args, :use_godaddy)
      
      return error_response("domain_name is required") unless domain_name.present?
      
      # Find GoDaddy connection if available
      connection = nil
      if use_godaddy
        connection = entity.connections
                          .joins(:integration)
                          .where(integrations: { slug: 'godaddy' }, status: 'active')
                          .first
      end
      
      service = CustomDomainService.new(entity: entity, user: user)
      result = service.register_domain(domain_name, subdomain: subdomain, connection: connection)
      
      if result[:success]
        custom_domain = result[:custom_domain]
        
        success_response(
          message: "Domain #{custom_domain.full_domain} has been registered!",
          custom_domain_id: custom_domain.id,
          domain_name: custom_domain.domain_name,
          full_domain: custom_domain.full_domain,
          cname_target: custom_domain.cname_target,
          instructions: result[:instructions],
          auto_dns: connection.present?,
          next_steps: connection.present? ? 
            "DNS will be configured automatically. Verification will begin in about 2 minutes." :
            "Add the CNAME record shown above to your DNS settings, then ask me to verify.",
          canvas_type: "custom_domains",
          canvas_data: { highlight_domain_id: custom_domain.id }
        )
      else
        error_response(result[:errors]&.join(", ") || result[:error])
      end
    end

    # =========================================
    # LIST DOMAINS
    # =========================================

    def list_domains
      domains = entity.custom_domains.order(created_at: :desc)
      
      if domains.empty?
        return success_response(
          message: "No custom domains configured yet. Would you like to add one?",
          domains: [],
          canvas_type: "custom_domains"
        )
      end
      
      domains_data = domains.map do |d|
        {
          id: d.id,
          domain_name: d.domain_name,
          full_domain: d.full_domain,
          cname_target: d.cname_target,
          web_status: d.web_status,
          email_status: d.email_status,
          ssl_status: d.ssl_status,
          is_primary: d.is_primary,
          fully_configured: d.fully_configured?,
          web_verified_at: d.web_verified_at,
          email_verified_at: d.email_verified_at
        }
      end
      
      success_response(
        message: "Found #{domains.count} custom domain(s)",
        domains: domains_data,
        canvas_type: "custom_domains"
      )
    end

    # =========================================
    # VERIFY WEB
    # =========================================

    def verify_web(args)
      domain = find_domain(args)
      return domain if domain.is_a?(Hash) # Error response
      
      service = CustomDomainService.new(custom_domain: domain)
      result = service.verify_web_dns
      
      if result[:success]
        success_response(
          message: "✅ Domain #{domain.full_domain} is verified! SSL certificate is being provisioned.",
          domain_id: domain.id,
          web_status: "verified",
          ssl_status: domain.reload.ssl_status,
          canvas_type: "custom_domains"
        )
      else
        success_response(
          message: "⏳ CNAME record not found yet. Please ensure you've added this record to your DNS:",
          domain_id: domain.id,
          expected_record: result[:expected],
          instructions: result[:instructions],
          canvas_type: "custom_domains"
        )
      end
    end

    # =========================================
    # VERIFY EMAIL
    # =========================================

    def verify_email(args)
      domain = find_domain(args)
      return domain if domain.is_a?(Hash)
      
      service = SesDomainService.new(custom_domain: domain)
      result = service.check_verification_status
      
      if result[:verified]
        success_response(
          message: "✅ Email sending is verified for #{domain.domain_name}! You can now send emails from this domain.",
          domain_id: domain.id,
          email_status: "verified",
          canvas_type: "custom_domains"
        )
      else
        success_response(
          message: "⏳ Email verification still in progress. Status: #{result[:status]}",
          domain_id: domain.id,
          status: result[:status],
          canvas_type: "custom_domains"
        )
      end
    end

    # =========================================
    # START EMAIL SETUP
    # =========================================

    def start_email_setup(args)
      domain = find_domain(args)
      return domain if domain.is_a?(Hash)
      
      unless domain.web_verified?
        return error_response("Web domain must be verified before setting up email sending")
      end
      
      service = SesDomainService.new(custom_domain: domain)
      result = service.start_verification
      
      if result[:success]
        success_response(
          message: "Email verification started for #{domain.domain_name}. Add the DNS records shown below.",
          domain_id: domain.id,
          dns_records: result[:dns_records],
          instructions: result[:instructions],
          canvas_type: "custom_domains"
        )
      else
        error_response(result[:error])
      end
    end

    # =========================================
    # SET PRIMARY
    # =========================================

    def set_primary(args)
      domain = find_domain(args)
      return domain if domain.is_a?(Hash)
      
      domain.update!(is_primary: true)
      
      success_response(
        message: "#{domain.full_domain} is now your primary domain",
        domain_id: domain.id,
        canvas_type: "custom_domains"
      )
    end

    # =========================================
    # DELETE DOMAIN
    # =========================================

    def delete_domain(args)
      domain = find_domain(args)
      return domain if domain.is_a?(Hash)
      
      domain_name = domain.full_domain
      domain.destroy!
      
      success_response(
        message: "Custom domain #{domain_name} has been removed",
        canvas_type: "custom_domains"
      )
    end

    # =========================================
    # HELPERS
    # =========================================

    def find_domain(args)
      domain_id = get_arg(args, :domain_id)
      
      unless domain_id.present?
        return error_response("domain_id is required")
      end
      
      domain = entity.custom_domains.find_by(id: domain_id)
      
      unless domain
        return error_response("Custom domain not found")
      end
      
      domain
    end
  end
end
