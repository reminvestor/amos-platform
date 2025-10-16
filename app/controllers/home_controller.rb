class HomeController < ApplicationController
  before_action :authenticate_user!

  def index
    # Recent campaign stats
    @campaigns = current_user.campaigns.order(created_at: :desc).limit(5)
    @campaign_count = current_user.campaigns.count
    @active_campaign_count = current_user.campaigns.where(status: "active").count

    # Contact stats
    @contact_count = current_user.contacts.count
    @contact_group_count = current_user.contact_groups.count
    @recent_contacts = current_user.contacts.order(created_at: :desc).limit(5)

    # Email template stats
    @template_count = current_user.email_templates.count

    # Email delivery stats
    @email_sent_count = EmailDelivery.joins(:campaign).where(campaigns: { user_id: current_user.id }).count
    @email_opened_count = EmailDelivery.joins(:campaign).where(campaigns: { user_id: current_user.id }).where.not(opened_at: nil).count
    @email_clicked_count = EmailDelivery.joins(:campaign).where(campaigns: { user_id: current_user.id }).where.not(clicked_at: nil).count

    # Open rate calculation
    @open_rate = @email_sent_count > 0 ? (@email_opened_count.to_f / @email_sent_count * 100).round(2) : 0
    @click_rate = @email_sent_count > 0 ? (@email_clicked_count.to_f / @email_sent_count * 100).round(2) : 0

    # Social media stats (if available)
    if defined?(SocialPost)
      @social_post_count = current_user.social_posts.count
      @recent_social_posts = current_user.social_posts.order(created_at: :desc).limit(3)
    else
      @social_post_count = 0
      @recent_social_posts = []
    end
  end
end
