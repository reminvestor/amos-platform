class AffiliateClick < ApplicationRecord
  belongs_to :affiliate

  validates :referral_code, presence: true

  scope :recent, -> { order(landed_at: :desc) }
  scope :for_date_range, ->(start_date, end_date) {
    where(landed_at: start_date..end_date) if start_date && end_date
  }
end
