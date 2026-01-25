# frozen_string_literal: true

# SesDomainService - Manages SES domain verification for custom email sending
#
# When a user wants to send emails from their own domain (e.g., hello@example.com)
# instead of from amos labs, they need to verify their domain in SES.
#
# This involves:
# 1. Creating a domain identity in SES
# 2. Adding DKIM records to their DNS
# 3. Adding SPF and DMARC records for deliverability
# 4. Verifying the records are configured correctly
#
class SesDomainService
  attr_reader :custom_domain, :entity
  
  def initialize(custom_domain:)
    @custom_domain = custom_domain
    @entity = custom_domain.entity
  end
  
  # =========================================
  # Start Email Domain Verification
  # =========================================
  
  def start_verification
    custom_domain.update!(email_status: 'verifying')
    
    if Rails.env.production?
      result = create_ses_identity
    else
      # Development mode - simulate verification
      result = simulate_verification
    end
    
    if result[:success]
      # Store the DNS records needed
      custom_domain.update!(
        dns_records: custom_domain.dns_records.merge(result[:dns_records]),
        ses_identity_arn: result[:identity_arn]
      )
      
      # If GoDaddy connection exists, auto-configure
      if custom_domain.can_auto_configure?
        auto_configure_email_dns(result[:dns_records])
      end
      
      {
        success: true,
        dns_records: result[:dns_records],
        instructions: email_dns_instructions(result[:dns_records])
      }
    else
      custom_domain.mark_email_failed!(result[:error])
      result
    end
  end
  
  # =========================================
  # Check Email Verification Status
  # =========================================
  
  def check_verification_status
    return simulate_verification_check unless Rails.env.production?
    
    require 'aws-sdk-sesv2'
    
    ses = Aws::SESV2::Client.new(region: ENV.fetch('AWS_REGION', 'us-east-1'))
    
    response = ses.get_email_identity(
      email_identity: custom_domain.domain_name
    )
    
    if response.verified_for_sending_status
      custom_domain.mark_email_verified!
      { success: true, verified: true, status: 'verified' }
    else
      dkim_status = response.dkim_attributes&.status
      { 
        success: true, 
        verified: false, 
        status: dkim_status,
        message: "DKIM status: #{dkim_status}. Continue waiting for DNS propagation."
      }
    end
  rescue Aws::SESV2::Errors::NotFoundException
    { success: false, error: 'Domain identity not found in SES' }
  rescue Aws::SESV2::Errors::ServiceError => e
    { success: false, error: e.message }
  end
  
  # =========================================
  # Send Email on Behalf of Customer
  # =========================================
  
  def send_email(from_address:, to_addresses:, subject:, body_html:, body_text: nil)
    return { success: false, error: 'Email not verified for this domain' } unless custom_domain.email_verified?
    
    # Validate from_address matches the custom domain
    unless from_address.downcase.end_with?("@#{custom_domain.domain_name.downcase}")
      return { success: false, error: "From address must use domain #{custom_domain.domain_name}" }
    end
    
    if Rails.env.production?
      send_via_ses(from_address, to_addresses, subject, body_html, body_text)
    else
      # Development mode - log the email
      Rails.logger.info "[DEV EMAIL] From: #{from_address}, To: #{to_addresses}, Subject: #{subject}"
      { success: true, message_id: "dev-#{SecureRandom.hex(8)}", mode: 'development' }
    end
  end
  
  private
  
  # =========================================
  # SES API Interactions
  # =========================================
  
  def create_ses_identity
    require 'aws-sdk-sesv2'
    
    ses = Aws::SESV2::Client.new(region: ENV.fetch('AWS_REGION', 'us-east-1'))
    
    # Create the domain identity
    response = ses.create_email_identity(
      email_identity: custom_domain.domain_name,
      dkim_signing_attributes: {
        next_signing_key_length: 'RSA_2048_BIT'
      },
      tags: [
        { key: 'Environment', value: Rails.env },
        { key: 'EntityId', value: entity.id.to_s },
        { key: 'CustomDomainId', value: custom_domain.id.to_s }
      ]
    )
    
    # Extract DKIM tokens
    dkim_tokens = response.dkim_attributes&.tokens || []
    
    # Build DNS records
    dns_records = build_dns_records(dkim_tokens)
    
    {
      success: true,
      identity_arn: "arn:aws:ses:#{ENV.fetch('AWS_REGION', 'us-east-1')}:#{ENV.fetch('AWS_ACCOUNT_ID', 'UNKNOWN')}:identity/#{custom_domain.domain_name}",
      dns_records: dns_records
    }
  rescue Aws::SESV2::Errors::AlreadyExistsException
    # Domain already exists, get the existing identity
    get_existing_identity
  rescue Aws::SESV2::Errors::ServiceError => e
    { success: false, error: e.message }
  end
  
  def get_existing_identity
    require 'aws-sdk-sesv2'
    
    ses = Aws::SESV2::Client.new(region: ENV.fetch('AWS_REGION', 'us-east-1'))
    
    response = ses.get_email_identity(email_identity: custom_domain.domain_name)
    
    dkim_tokens = response.dkim_attributes&.tokens || []
    
    {
      success: true,
      identity_arn: "arn:aws:ses:#{ENV.fetch('AWS_REGION', 'us-east-1')}:#{ENV.fetch('AWS_ACCOUNT_ID', 'UNKNOWN')}:identity/#{custom_domain.domain_name}",
      dns_records: build_dns_records(dkim_tokens),
      already_existed: true
    }
  rescue Aws::SESV2::Errors::ServiceError => e
    { success: false, error: e.message }
  end
  
  def build_dns_records(dkim_tokens)
    domain = custom_domain.domain_name
    
    {
      dkim: dkim_tokens.map do |token|
        {
          type: 'CNAME',
          name: "#{token}._domainkey.#{domain}",
          value: "#{token}.dkim.amazonses.com"
        }
      end,
      spf: {
        type: 'TXT',
        name: domain,
        value: 'v=spf1 include:amazonses.com ~all'
      },
      dmarc: {
        type: 'TXT',
        name: "_dmarc.#{domain}",
        value: "v=DMARC1; p=none; rua=mailto:dmarc-reports@#{domain}"
      },
      mail_from: {
        type: 'MX',
        name: "mail.#{domain}",
        value: "10 feedback-smtp.#{ENV.fetch('AWS_REGION', 'us-east-1')}.amazonses.com"
      },
      mail_from_spf: {
        type: 'TXT',
        name: "mail.#{domain}",
        value: 'v=spf1 include:amazonses.com ~all'
      }
    }
  end
  
  def send_via_ses(from_address, to_addresses, subject, body_html, body_text)
    require 'aws-sdk-sesv2'
    
    ses = Aws::SESV2::Client.new(region: ENV.fetch('AWS_REGION', 'us-east-1'))
    
    to_addresses = Array(to_addresses)
    
    response = ses.send_email(
      from_email_address: from_address,
      destination: {
        to_addresses: to_addresses
      },
      content: {
        simple: {
          subject: {
            data: subject,
            charset: 'UTF-8'
          },
          body: {
            text: body_text.present? ? { data: body_text, charset: 'UTF-8' } : nil,
            html: { data: body_html, charset: 'UTF-8' }
          }.compact
        }
      }
    )
    
    { success: true, message_id: response.message_id }
  rescue Aws::SESV2::Errors::ServiceError => e
    { success: false, error: e.message }
  end
  
  # =========================================
  # Development Mode Simulation
  # =========================================
  
  def simulate_verification
    # Simulate DKIM tokens
    dkim_tokens = 3.times.map { SecureRandom.alphanumeric(32).downcase }
    
    {
      success: true,
      identity_arn: "arn:aws:ses:us-east-1:123456789:identity/#{custom_domain.domain_name}",
      dns_records: build_dns_records(dkim_tokens)
    }
  end
  
  def simulate_verification_check
    # In development, auto-verify after creation
    custom_domain.mark_email_verified!
    { success: true, verified: true, status: 'verified', mode: 'development' }
  end
  
  # =========================================
  # Auto-Configuration via GoDaddy
  # =========================================
  
  def auto_configure_email_dns(dns_records)
    return unless custom_domain.can_auto_configure?
    
    connection = custom_domain.connection
    executor = IntegrationExecutorService.new(connection: connection)
    
    # Collect all records to add
    records_to_add = []
    
    # DKIM records
    dns_records[:dkim]&.each do |dkim|
      records_to_add << {
        type: 'CNAME',
        name: dkim[:name].gsub(".#{custom_domain.domain_name}", ''),
        data: dkim[:value],
        ttl: 3600
      }
    end
    
    # SPF record (TXT)
    if dns_records[:spf]
      records_to_add << {
        type: 'TXT',
        name: '@',
        data: dns_records[:spf][:value],
        ttl: 3600
      }
    end
    
    # DMARC record (TXT)
    if dns_records[:dmarc]
      records_to_add << {
        type: 'TXT',
        name: '_dmarc',
        data: dns_records[:dmarc][:value],
        ttl: 3600
      }
    end
    
    # Add records via GoDaddy
    executor.execute(
      'godaddy.add_dns_record',
      domain: custom_domain.domain_name,
      records: records_to_add
    )
    
    # Schedule verification check
    CustomDomainVerificationJob.set(wait: 5.minutes).perform_later(custom_domain.id, 'email')
  end
  
  # =========================================
  # Instructions Helper
  # =========================================
  
  def email_dns_instructions(dns_records)
    dkim_rows = dns_records[:dkim]&.map do |dkim|
      "| CNAME | #{dkim[:name]} | #{dkim[:value]} |"
    end&.join("\n") || ""
    
    <<~INSTRUCTIONS
      ## Email DNS Configuration for #{custom_domain.domain_name}
      
      Add the following DNS records to enable email sending from your domain:
      
      ### DKIM Records (Required - Add all 3)
      | Type  | Name | Value |
      |-------|------|-------|
      #{dkim_rows}
      
      ### SPF Record (Required)
      | Type | Name | Value |
      |------|------|-------|
      | TXT  | #{dns_records[:spf][:name]} | #{dns_records[:spf][:value]} |
      
      ### DMARC Record (Recommended)
      | Type | Name | Value |
      |------|------|-------|
      | TXT  | #{dns_records[:dmarc][:name]} | #{dns_records[:dmarc][:value]} |
      
      **Note:** DNS propagation can take up to 72 hours, but usually completes within 1-2 hours.
      
      Once configured, click "Verify Email Domain" to complete setup.
    INSTRUCTIONS
  end
end
