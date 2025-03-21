module CampaignTrackingHelper
  # Generate a click tracking URL for a link in an email
  def track_click_url(email_delivery_id, url)
    email_click_url(email_delivery_id, url: url, host: ActionMailer::Base.default_url_options[:host])
  end
end
