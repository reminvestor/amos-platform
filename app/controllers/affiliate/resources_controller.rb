class Affiliate::ResourcesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_affiliate
  skip_before_action :check_token_balance
  skip_before_action :check_onboarding_status

  def index
    @affiliate = current_user.affiliate
    @social_posts = social_post_templates
    @email_templates = email_template_examples
  end

  private

  def ensure_affiliate
    unless current_user.affiliate&.active?
      redirect_to affiliate_apply_path, alert: "You must be an approved affiliate to access resources."
    end
  end

  def social_post_templates
    [
      {
        platform: "Twitter",
        text: "Just discovered AMOS - the AI-powered marketing automation platform that's changing the game! 🚀 Check it out: [YOUR_REFERRAL_LINK] #Marketing #AI"
      },
      {
        platform: "LinkedIn",
        text: "I've been using AMOS for my marketing automation and it's been a game-changer. The AI-powered features save me hours every week. If you're looking to streamline your marketing, definitely check it out: [YOUR_REFERRAL_LINK]"
      },
      {
        platform: "Facebook",
        text: "Loving AMOS! 💙 This marketing automation platform has made my life so much easier. AI-powered campaigns, landing pages, and more. Highly recommend: [YOUR_REFERRAL_LINK]"
      }
    ]
  end

  def email_template_examples
    [
      {
        subject: "Transform Your Marketing with AMOS",
        preview: "I wanted to share a tool that's been incredibly helpful for my marketing efforts..."
      },
      {
        subject: "The AI Marketing Tool You've Been Looking For",
        preview: "If you're struggling with marketing automation, I have a solution for you..."
      }
    ]
  end
end
