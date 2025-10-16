class Affiliate < ApplicationRecord
  belongs_to :user
  belongs_to :approved_by, class_name: 'AdminUser', optional: true
  has_many :referrals, dependent: :restrict_with_error
  has_many :affiliate_clicks, dependent: :destroy
  has_many :commissions, dependent: :restrict_with_error
  has_many :payouts, dependent: :restrict_with_error

  enum :status, { pending: 0, active: 1, suspended: 2, terminated: 3 }
  enum :tier, { bronze: 0, silver: 1, gold: 2 }

  validates :affiliate_code, presence: true, uniqueness: true
  validates :commission_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  before_validation :generate_affiliate_code, on: :create

  scope :filter_by_status, ->(status) { where(status: status) if status.present? }
  scope :filter_by_tier, ->(tier) { where(tier: tier) if tier.present? }
  scope :search, ->(query) {
    if query.present?
      joins(:user).where('users.email ILIKE ? OR users.first_name ILIKE ? OR users.last_name ILIKE ? OR affiliates.affiliate_code ILIKE ?',
                         "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%")
    end
  }
  scope :with_approved_commissions, -> { joins(:commissions).where(commissions: { status: :approved }).distinct }
  scope :with_approved_commissions_above_threshold, ->(amount) {
    joins(:commissions)
      .where(commissions: { status: :approved })
      .group('affiliates.id')
      .having('SUM(commissions.amount) >= ?', amount)
  }

  def total_clicks
    affiliate_clicks.count
  end

  def total_referrals
    referrals.count
  end

  def total_conversions
    referrals.converted.count
  end

  def total_earned
    commissions.approved.sum(:amount) + commissions.paid.sum(:amount)
  end

  def pending_commissions_amount
    commissions.pending.sum(:amount)
  end

  def approved_commissions_amount
    commissions.approved.sum(:amount)
  end

  def total_paid_out
    payouts.completed.sum(:amount)
  end

  def conversion_rate
    return 0 if total_clicks.zero?
    (total_conversions.to_f / total_clicks * 100).round(2)
  end

  private

  def generate_affiliate_code
    self.affiliate_code ||= SecureRandom.alphanumeric(8).upcase
  end
end
