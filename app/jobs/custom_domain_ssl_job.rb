# frozen_string_literal: true

# CustomDomainSslJob - Provisions and monitors SSL certificates for custom domains
#
class CustomDomainSslJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  
  def perform(custom_domain_id)
    custom_domain = CustomDomain.find_by(id: custom_domain_id)
    return unless custom_domain
    return unless custom_domain.web_verified?
    
    service = CustomDomainService.new(custom_domain: custom_domain)
    result = service.provision_ssl_certificate
    
    if result[:success]
      Rails.logger.info "🔒 SSL provisioned for: #{custom_domain.full_domain}"
    else
      Rails.logger.warn "⚠️ SSL provisioning failed for #{custom_domain.full_domain}: #{result[:error]}"
    end
  end
end
