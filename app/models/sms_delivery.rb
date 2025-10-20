class SmsDelivery < ApplicationRecord
  belongs_to :sms_campaign
  belongs_to :contact

  validates :to_number, presence: true
  validates :status, inclusion: { in: %w[queued sent delivered failed undelivered] }

  scope :delivered, -> { where(status: 'delivered') }
  scope :failed, -> { where(status: 'failed') }
  scope :pending, -> { where(status: %w[queued sent]) }
end
