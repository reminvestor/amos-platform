class Commission < ApplicationRecord
  include Auditable

  belongs_to :affiliate
  belongs_to :referral
  belongs_to :entity
  belongs_to :subscription_event, optional: true
  belongs_to :approved_by, class_name: 'AdminUser', optional: true

  enum :status, { pending: 0, approved: 1, paid: 2, cancelled: 3 }

  validates :amount, numericality: { greater_than: 0 }
  validates :commission_type, presence: true

  scope :filter_by_status, ->(status) { where(status: status) if status.present? }
  scope :filter_by_date_range, ->(date_from, date_to) {
    where(earned_at: date_from..date_to) if date_from && date_to
  }
  scope :filter_by_affiliate, ->(affiliate_id) { where(affiliate_id: affiliate_id) if affiliate_id.present? }
  scope :recent, -> { order(earned_at: :desc) }

  def approve!(admin_user)
    update!(
      status: :approved,
      approved_at: Time.current,
      approved_by: admin_user
    )
  end

  def cancel!
    update!(status: :cancelled)
  end

  def mark_as_paid!
    update!(status: :paid)
  end
end
