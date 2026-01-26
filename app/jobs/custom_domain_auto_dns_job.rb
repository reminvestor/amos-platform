# frozen_string_literal: true

# CustomDomainAutoDnsJob - Auto-configures DNS via GoDaddy integration
#
class CustomDomainAutoDnsJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  
  def perform(custom_domain_id)
    custom_domain = CustomDomain.find_by(id: custom_domain_id)
    return unless custom_domain
    return unless custom_domain.can_auto_configure?
    
    service = CustomDomainService.new(custom_domain: custom_domain)
    result = service.auto_configure_dns
    
    if result[:success]
      Rails.logger.info "🤖 Auto-configured DNS for: #{custom_domain.full_domain}"
    else
      Rails.logger.warn "⚠️ Auto-DNS failed for #{custom_domain.full_domain}: #{result[:error]}"
    end
  end
end
