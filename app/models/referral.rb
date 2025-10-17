class Referral < ApplicationRecord
  belongs_to :affiliate
  belongs_to :referred_user, class_name: 'User', optional: true
  belongs_to :referred_entity, class_name: 'Entity', optional: true
  has_many :commissions, dependent: :restrict_with_error

  enum :status, { pending: 0, converted: 1, cancelled: 2 }

  validates :referral_code_used, presence: true

  scope :filter_by_status, ->(status) { where(status: status) if status.present? }
  scope :recent, -> { order(created_at: :desc) }
end
