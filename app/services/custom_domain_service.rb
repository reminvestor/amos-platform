# frozen_string_literal: true

# CustomDomainService - Manages custom domain setup, verification, and publishing
#
# Handles:
# - Domain registration and CNAME target generation
# - DNS verification (checking if CNAME is configured correctly)
# - SSL certificate provisioning via AWS ACM
# - Integration with GoDaddy for auto-DNS configuration
#
class CustomDomainService
  CNAME_BASE_DOMAIN = 'custom.amoslabs.com'
  
  attr_reader :custom_domain, :entity, :user
  
  def initialize(custom_domain: nil, entity: nil, user: nil)
    @custom_domain = custom_domain
    @entity = entity || custom_domain&.entity
    @user = user || custom_domain&.user
  end
  
  # =========================================
  # Domain Registration
  # =========================================
  
  def register_domain(domain_name, subdomain: nil, connection: nil)
    # Validate domain isn't already registered
    if CustomDomain.exists?(domain_name: domain_name.downcase)
      return { success: false, error: "Domain #{domain_name} is already registered" }
    end
    
    # Create the custom domain record
    custom_domain = CustomDomain.new(
      entity: entity,
      user: user,
      domain_name: domain_name.downcase,
      subdomain: subdomain,
      connection: connection
    )
    
    if custom_domain.save
      # If GoDaddy connection provided, attempt auto-configuration
      if connection.present?
        schedule_auto_dns_configuration(custom_domain)
      end
      
      { 
        success: true, 
        custom_domain: custom_domain,
        cname_target: custom_domain.cname_target,
        instructions: dns_setup_instructions(custom_domain)
      }
    else
      { success: false, errors: custom_domain.errors.full_messages }
    end
  end
  
  # =========================================
  # DNS Verification
  # =========================================
  
  def verify_web_dns
    return { success: false, error: 'No custom domain specified' } unless custom_domain
    
    custom_domain.update!(web_status: 'verifying')
    
    # Check CNAME record
    cname_verified = verify_cname_record
    
    if cname_verified
      custom_domain.mark_web_verified!
      
      # Trigger SSL provisioning
      provision_ssl_certificate
      
      { 
        success: true, 
        message: "Domain #{custom_domain.full_domain} verified! SSL certificate is being provisioned.",
        ssl_status: custom_domain.ssl_status
      }
    else
      custom_domain.mark_web_failed!("CNAME record not found or incorrect")
      
      { 
        success: false, 
        error: "CNAME record not found",
        expected: {
          type: 'CNAME',
          name: custom_domain.subdomain.presence || '@',
          value: custom_domain.cname_target
        },
        instructions: dns_setup_instructions(custom_domain)
      }
    end
  end
  
  def verify_cname_record
    require 'resolv'
    
    begin
      resolver = Resolv::DNS.new
      
      # Check the full domain
      domain_to_check = custom_domain.full_domain
      
      resources = resolver.getresources(domain_to_check, Resolv::DNS::Resource::IN::CNAME)
      
      resources.any? do |resource|
        resource.name.to_s.downcase == custom_domain.cname_target.downcase ||
        resource.name.to_s.downcase.include?(CNAME_BASE_DOMAIN)
      end
    rescue Resolv::ResolvError => e
      Rails.logger.warn "DNS resolution error for #{custom_domain.full_domain}: #{e.message}"
      false
    rescue => e
      Rails.logger.error "CNAME verification error: #{e.message}"
      false
    end
  end
  
  # =========================================
  # SSL Certificate Provisioning
  # =========================================
  
  def provision_ssl_certificate
    return { success: false, error: 'Domain not verified' } unless custom_domain.web_verified?
    
    custom_domain.update!(ssl_status: 'provisioning')
    
    # In production, use AWS ACM to request a certificate
    if Rails.env.production?
      provision_acm_certificate
    else
      # In development, simulate SSL provisioning
      custom_domain.update!(
        ssl_status: 'active',
        ssl_provisioned_at: Time.current
      )
      { success: true, message: 'SSL certificate provisioned (development mode)' }
    end
  end
  
  def provision_acm_certificate
    require 'aws-sdk-acm'
    
    acm = Aws::ACM::Client.new(region: ENV.fetch('AWS_REGION', 'us-east-1'))
    
    # Request certificate for domain and www subdomain
    domains = [custom_domain.full_domain]
    domains << custom_domain.www_domain if custom_domain.subdomain.blank?
    
    response = acm.request_certificate(
      domain_name: custom_domain.full_domain,
      subject_alternative_names: domains,
      validation_method: 'DNS',
      tags: [
        { key: 'Environment', value: Rails.env },
        { key: 'EntityId', value: entity.id.to_s },
        { key: 'CustomDomainId', value: custom_domain.id.to_s }
      ]
    )
    
    custom_domain.update!(ssl_certificate_arn: response.certificate_arn)
    
    # Schedule a job to check certificate status
    CustomDomainSslCheckJob.set(wait: 5.minutes).perform_later(custom_domain.id)
    
    { 
      success: true, 
      certificate_arn: response.certificate_arn,
      message: 'SSL certificate requested. Validation in progress.'
    }
  rescue Aws::ACM::Errors::ServiceError => e
    custom_domain.mark_ssl_failed!(e.message)
    { success: false, error: e.message }
  end
  
  # =========================================
  # GoDaddy Auto-DNS Configuration
  # =========================================
  
  def auto_configure_dns
    return { success: false, error: 'No GoDaddy connection' } unless custom_domain.connection.present?
    
    connection = custom_domain.connection
    
    begin
      api_service = IntegrationApiService.new(connection)
      operation = connection.integration.integration_operations.find_by(operation_id: 'godaddy.add_dns_record')
      
      return { success: false, error: 'GoDaddy add_dns_record operation not found' } unless operation
      
      # Build the CNAME record payload
      records_payload = [
        {
          type: 'CNAME',
          name: custom_domain.subdomain.presence || '@',
          data: custom_domain.cname_target,
          ttl: 3600
        }
      ]
      
      # Execute via IntegrationApiService (PATCH /v1/domains/{domain}/records)
      response = api_service.execute_operation(
        operation,
        params: { domain: custom_domain.domain_name },
        body: records_payload
      )
      
      if response.success?
        custom_domain.update!(auto_dns_configured: true)
        
        # Start verification (DNS propagation may take time)
        CustomDomainVerificationJob.set(wait: 2.minutes).perform_later(custom_domain.id, 'web')
        
        { 
          success: true, 
          message: 'DNS records configured automatically. Verification will begin shortly.'
        }
      else
        { success: false, error: "GoDaddy API error: #{response.code} - #{response.body}" }
      end
    rescue => e
      Rails.logger.error "Auto DNS configuration failed: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  # =========================================
  # Publishing Helpers
  # =========================================
  
  def assign_to_landing_page(landing_page)
    return { success: false, error: 'Domain not fully configured' } unless custom_domain.fully_configured?
    
    landing_page.update!(custom_domain: custom_domain)
    
    {
      success: true,
      url: custom_domain.landing_page_url(landing_page)
    }
  end
  
  def assign_to_website(website)
    return { success: false, error: 'Domain not fully configured' } unless custom_domain.fully_configured?
    
    website.update!(custom_domain: custom_domain)
    
    {
      success: true,
      url: custom_domain.website_url(website)
    }
  end
  
  # =========================================
  # Helpers
  # =========================================
  
  def dns_setup_instructions(domain = custom_domain)
    <<~INSTRUCTIONS
      ## DNS Configuration for #{domain.full_domain}
      
      Add the following CNAME record to your DNS settings:
      
      | Type  | Name                                    | Value                          | TTL  |
      |-------|----------------------------------------|--------------------------------|------|
      | CNAME | #{domain.subdomain.presence || '@'}    | #{domain.cname_target}         | 3600 |
      
      #{domain.subdomain.blank? ? "| CNAME | www                                    | #{domain.cname_target}         | 3600 |" : ""}
      
      **Note:** DNS changes can take up to 48 hours to propagate, but usually complete within 15 minutes.
      
      Once configured, click "Verify Domain" to complete setup.
    INSTRUCTIONS
  end
  
  private
  
  def schedule_auto_dns_configuration(domain)
    CustomDomainAutoDnsJob.perform_later(domain.id)
  end
end
