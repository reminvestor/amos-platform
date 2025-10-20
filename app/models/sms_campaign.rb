class SmsCampaign < ApplicationRecord
  belongs_to :entity
  has_many :sms_deliveries, dependent: :destroy

  validates :name, presence: true
  validates :message_body, presence: true, length: { maximum: 1600 } # SMS limit
  validates :status, inclusion: { in: %w[draft scheduled sending sent failed] }

  scope :draft, -> { where(status: 'draft') }
  scope :scheduled, -> { where(status: 'scheduled') }
  scope :sent, -> { where(status: 'sent') }

  def send_now!
    ProcessSmsCampaignJob.perform_later(id)
  end

  def delivery_rate
    return 0 if total_recipients.zero?
    (delivered_count.to_f / total_recipients * 100).round(2)
  end

  def failure_rate
    return 0 if total_recipients.zero?
    (failed_count.to_f / total_recipients * 100).round(2)
  end
end
