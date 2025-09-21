class AdminUser < ApplicationRecord
  has_secure_password
  
  # Audit trail
  has_many :admin_activities
  
  # Roles
  enum :role, { 
    viewer: 0,      # Read-only access
    editor: 1,      # Can modify settings
    super_admin: 2  # Full access
  }
  
  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, :last_name, presence: true
  validates :role, presence: true
  
  # Scopes
  scope :active, -> { where(locked_at: nil) }
  
  # Callbacks
  before_save :downcase_email
  
  def full_name
    "#{first_name} #{last_name}"
  end
  
  def locked?
    locked_at.present?
  end
  
  def lock!
    update!(locked_at: Time.current)
  end
  
  def unlock!
    update!(locked_at: nil, failed_login_attempts: 0)
  end
  
  def record_login!
    update!(
      last_login_at: Time.current,
      login_count: login_count + 1,
      failed_login_attempts: 0
    )
  end
  
  def record_failed_login!
    increment!(:failed_login_attempts)
    lock! if failed_login_attempts >= 5
  end
  
  private
  
  def downcase_email
    self.email = email.downcase if email.present?
  end
end
