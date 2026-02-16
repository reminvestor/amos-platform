# frozen_string_literal: true

# CustomDomain - Manages custom domains for landing pages, websites, and email sending
#
# Users configure a CNAME record once, and all their published content
# becomes available at their custom domain. Also handles SES domain
# verification for sending emails from customer domains.
#
class CustomDomain < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :connection, optional: true  # GoDaddy connection for auto-DNS
  
  has_many :landing_pages, dependent: :nullify
  has_many :websites, dependent: :nullify
  has_many :module_canvases, dependent: :nullify
  
  # Validations
  validates :domain_name, presence: true, uniqueness: { case_sensitive: false }
  validates :cname_target, presence: true, uniqueness: true
  validates :domain_name, format: { 
    with: /\A[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,}\z/i,
    message: "must be a valid domain (e.g., example.com)"
  }
  
  # Statuses
  WEB_STATUSES = %w[pending verifying verified failed].freeze
  EMAIL_STATUSES = %w[pending verifying verified failed].freeze
  SSL_STATUSES = %w[pending provisioning active failed].freeze
  
  validates :web_status, inclusion: { in: WEB_STATUSES }
  validates :email_status, inclusion: { in: EMAIL_STATUSES }
  validates :ssl_status, inclusion: { in: SSL_STATUSES }
  
  # Scopes
  scope :verified, -> { where(web_status: 'verified') }
  scope :with_ssl, -> { where(ssl_status: 'active') }
  scope :email_verified, -> { where(email_status: 'verified') }
  scope :primary, -> { where(is_primary: true) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  
  # Callbacks
  before_validation :generate_cname_target, on: :create
  before_validation :normalize_domain_name
  after_create :generate_verification_token
  after_update :handle_primary_change, if: :saved_change_to_is_primary?
  
  # =========================================
  # Domain Name Helpers
  # =========================================
  
  def full_domain
    subdomain.present? ? "#{subdomain}.#{domain_name}" : domain_name
  end
  
  def root_domain
    domain_name
  end
  
  def www_domain
    "www.#{domain_name}"
  end
  
  # =========================================
  # Verification Status Helpers
  # =========================================
  
  def web_verified?
    web_status == 'verified'
  end
  
  def email_verified?
    email_status == 'verified'
  end
  
  def ssl_active?
    ssl_status == 'active'
  end
  
  def fully_configured?
    web_verified? && ssl_active?
  end
  
  def ready_for_email?
    email_verified?
  end
  
  # =========================================
  # CNAME Record Info
  # =========================================
  
  def cname_record
    {
      type: 'CNAME',
      name: subdomain.present? ? subdomain : '@',
      value: cname_target,
      ttl: 3600
    }
  end
  
  def www_cname_record
    return nil if subdomain.present?  # Only for root domains
    
    {
      type: 'CNAME',
      name: 'www',
      value: cname_target,
      ttl: 3600
    }
  end
  
  # =========================================
  # DNS Records for Email (SES)
  # =========================================
  
  def email_dns_records
    dns_records.with_indifferent_access
  end
  
  def dkim_records
    email_dns_records[:dkim] || []
  end
  
  def spf_record
    email_dns_records[:spf]
  end
  
  def dmarc_record
    email_dns_records[:dmarc]
  end
  
  # =========================================
  # URL Helpers
  # =========================================
  
  def base_url
    return nil unless fully_configured?
    "https://#{full_domain}"
  end
  
  def landing_page_url(landing_page)
    return nil unless fully_configured?
    "#{base_url}/#{landing_page.slug}"
  end
  
  def website_url(website)
    return nil unless fully_configured?
    base_url
  end
  
  def app_url(module_canvas)
    return nil unless fully_configured?
    "#{base_url}/app/#{module_canvas.app_module.slug}"
  end
  
  # =========================================
  # Verification Actions
  # =========================================
  
  def start_web_verification!
    update!(web_status: 'verifying')
    CustomDomainVerificationJob.perform_later(id, 'web')
  end
  
  def start_email_verification!
    update!(email_status: 'verifying')
    CustomDomainVerificationJob.perform_later(id, 'email')
  end
  
  def mark_web_verified!
    update!(
      web_status: 'verified',
      web_verified_at: Time.current
    )
    provision_ssl! unless ssl_active?
  end
  
  def mark_email_verified!
    update!(
      email_status: 'verified',
      email_verified_at: Time.current
    )
  end
  
  def mark_web_failed!(error = nil)
    update!(web_status: 'failed', last_error: error)
  end
  
  def mark_email_failed!(error = nil)
    update!(email_status: 'failed', last_error: error)
  end
  
  def provision_ssl!
    update!(ssl_status: 'provisioning')
    CustomDomainSslJob.perform_later(id)
  end
  
  # =========================================
  # GoDaddy Auto-Configuration
  # =========================================
  
  def can_auto_configure?
    connection.present? && connection.connected?
  end
  
  def auto_configure_dns!
    return false unless can_auto_configure?
    
    CustomDomainAutoDnsJob.perform_later(id)
    true
  end
  
  private
  
  def generate_cname_target
    return if cname_target.present?
    
    # Generate a unique subdomain for this customer
    # Format: abc123.custom.amoslabs.com
    unique_id = SecureRandom.alphanumeric(8).downcase
    self.cname_target = "#{unique_id}.custom.amoslabs.com"
  end
  
  def normalize_domain_name
    return unless domain_name.present?
    
    # Remove protocol if present
    self.domain_name = domain_name.downcase
                                  .gsub(%r{^https?://}, '')
                                  .gsub(%r{/$}, '')
                                  .strip
  end
  
  def generate_verification_token
    update_column(:verification_token, SecureRandom.hex(16))
  end
  
  def handle_primary_change
    return unless is_primary?
    
    # Ensure only one primary domain per entity
    CustomDomain.where(entity_id: entity_id)
                .where.not(id: id)
                .update_all(is_primary: false)
  end
end
