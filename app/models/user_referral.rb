class UserReferral < ApplicationRecord
  belongs_to :referrer, class_name: 'User'
  belongs_to :referred_user, class_name: 'User', optional: true

  enum :status, { pending: 0, signed_up: 1, expired: 2 }

  validates :referred_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  validates :referred_email, uniqueness: { scope: :referrer_id, message: "has already been invited by you" }
  validate :referrer_limit, on: :create
  validate :not_self_referral

  before_validation :generate_token, on: :create
  before_validation :set_expiration, on: :create

  scope :pending, -> { where(status: :pending) }
  scope :active, -> { pending.where('expires_at > ?', Time.current) }
  scope :by_referrer, ->(user) { where(referrer: user) }

  TOKENS_ON_INVITE = 50_000
  TOKENS_ON_SIGNUP = 100_000
  MAX_REFERRALS = 5

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def mark_signed_up!(user)
    return if signed_up?
    
    transaction do
      update!(
        status: :signed_up,
        referred_user: user,
        signed_up_at: Time.current,
        tokens_awarded: tokens_awarded + TOKENS_ON_SIGNUP
      )
      
      # Credit bonus tokens to referrer
      if referrer.user_billing_account
        referrer.user_billing_account.credit_tokens!(
          amount: TOKENS_ON_SIGNUP,
          transaction_type: 'credit',
          category: 'referral_bonus',
          description: "Bonus for #{referred_email} signing up"
        )
        Rails.logger.info "🎁 Credited #{TOKENS_ON_SIGNUP} referral bonus tokens to user #{referrer.id}"
      end
    end
  end

  def self.process_signup(email)
    referral = UserReferral.pending.find_by(referred_email: email.downcase.strip)
    return unless referral
    
    user = User.find_by(email: email.downcase.strip)
    referral.mark_signed_up!(user) if user
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  def set_expiration
    self.expires_at ||= 30.days.from_now
  end

  def referrer_limit
    return unless referrer
    
    existing_count = UserReferral.by_referrer(referrer).count
    if existing_count >= MAX_REFERRALS
      errors.add(:base, "You have reached the maximum of #{MAX_REFERRALS} referrals")
    end
  end

  def not_self_referral
    return unless referrer && referred_email
    
    if referrer.email.downcase == referred_email.downcase
      errors.add(:referred_email, "cannot be your own email")
    end
  end
end
