# frozen_string_literal: true

# CustomDomainVerificationJob - Background job to verify custom domain DNS
#
# Checks if the required DNS records are configured correctly for:
# - Web publishing (CNAME record)
# - Email sending (DKIM, SPF, DMARC records)
#
class CustomDomainVerificationJob < ApplicationJob
  queue_as :default
  
  # Retry up to 10 times over several hours
  retry_on StandardError, wait: :polynomially_longer, attempts: 10
  
  def perform(custom_domain_id, verification_type)
    custom_domain = CustomDomain.find_by(id: custom_domain_id)
    return unless custom_domain
    
    case verification_type.to_s
    when 'web'
      verify_web_domain(custom_domain)
    when 'email'
      verify_email_domain(custom_domain)
    else
      Rails.logger.error "Unknown verification type: #{verification_type}"
    end
  end
  
  private
  
  def verify_web_domain(custom_domain)
    service = CustomDomainService.new(custom_domain: custom_domain)
    result = service.verify_web_dns
    
    if result[:success]
      Rails.logger.info "✅ Web domain verified: #{custom_domain.full_domain}"
      
      # Notify user
      notify_user(custom_domain, :web_verified)
    else
      Rails.logger.info "⏳ Web domain not yet verified: #{custom_domain.full_domain}"
      
      # Schedule retry if still verifying
      if custom_domain.web_status == 'verifying'
        self.class.set(wait: 5.minutes).perform_later(custom_domain.id, 'web')
      end
    end
  end
  
  def verify_email_domain(custom_domain)
    service = SesDomainService.new(custom_domain: custom_domain)
    result = service.check_verification_status
    
    if result[:verified]
      Rails.logger.info "✅ Email domain verified: #{custom_domain.domain_name}"

      # Auto-configure entity email settings if not already set
      entity = custom_domain.entity
      if entity.from_email.blank?
        entity.update(
          from_email: "hello@#{custom_domain.domain_name}",
          sender_name: entity.sender_name.presence || entity.name
        )
        Rails.logger.info "✅ Auto-configured entity #{entity.id} from_email to hello@#{custom_domain.domain_name}"
      end

      # Notify user
      notify_user(custom_domain, :email_verified)
    else
      Rails.logger.info "⏳ Email domain not yet verified: #{custom_domain.domain_name}"
      
      # Schedule retry if still verifying
      if custom_domain.email_status == 'verifying'
        self.class.set(wait: 10.minutes).perform_later(custom_domain.id, 'email')
      end
    end
  end
  
  def notify_user(custom_domain, event_type)
    # Create a notification for the user
    case event_type
    when :web_verified
      message = "Your domain #{custom_domain.full_domain} is now verified! You can publish landing pages and websites to this domain."
    when :email_verified
      message = "Your domain #{custom_domain.domain_name} is now verified for email sending! You can send emails from addresses like hello@#{custom_domain.domain_name}."
    end
    
    # Create work inbox item
    WorkInboxItem.create(
      entity: custom_domain.entity,
      user: custom_domain.user,
      work_type: 'domain_verified',
      title: "Domain Verified: #{custom_domain.domain_name}",
      content: message,
      source_type: 'CustomDomain',
      source_id: custom_domain.id,
      metadata: {
        domain_name: custom_domain.domain_name,
        event_type: event_type.to_s,
        web_status: custom_domain.web_status,
        email_status: custom_domain.email_status
      }
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end
end
