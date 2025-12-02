# frozen_string_literal: true

# Alias for Campaign model
# This provides backwards compatibility for code that references EmailCampaign
# The actual model is Campaign (app/models/campaign.rb)
class EmailCampaign < Campaign
end

