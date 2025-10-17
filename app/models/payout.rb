class Payout < ApplicationRecord
  include Auditable

  belongs_to :affiliate
  belongs_to :processed_by, class_name: 'AdminUser', optional: true

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :amount, numericality: { greater_than: 0 }
  validates :payment_method, presence: true

  scope :filter_by_status, ->(status) { where(status: status) if status.present? }
  scope :recent, -> { order(created_at: :desc) }

  def mark_completed!(admin_user, payment_reference = nil)
    update!(
      status: :completed,
      payment_reference: payment_reference,
      processed_by: admin_user
    )

    # Mark associated commissions as paid
    Commission.where(id: commission_ids).update_all(status: :paid) if commission_ids.present?
  end
end
