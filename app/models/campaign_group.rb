class CampaignGroup < ApplicationRecord
  belongs_to :campaign
  belongs_to :contact_group
  
  # Validations
  validates :contact_group_id, uniqueness: { scope: :campaign_id, message: "is already included in this campaign" }
end
