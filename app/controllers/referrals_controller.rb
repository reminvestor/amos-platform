class ReferralsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: [:create]

  def create
    emails = params[:emails] || []
    emails = emails.map(&:strip).reject(&:blank?).uniq.first(5)

    if emails.empty?
      render json: { error: "Please enter at least one email address" }, status: :unprocessable_entity
      return
    end

    created_referrals = []
    errors = []
    tokens_earned = 0

    emails.each do |email|
      # Check if already a user
      if User.exists?(email: email.downcase)
        errors << "#{email} is already an AMOS user"
        next
      end

      referral = UserReferral.new(
        referrer: current_user,
        referred_email: email.downcase
      )

      if referral.save
        # Send invitation email
        ReferralMailer.invite_email(referral).deliver_later
        referral.update!(email_sent_at: Time.current)

        # Credit tokens immediately for submitting
        if current_user.user_billing_account
          current_user.user_billing_account.credit_tokens!(
            UserReferral::TOKENS_ON_INVITE,
            category: 'referral_invite',
            description: "Referral invitation sent to #{email}"
          )
          tokens_earned += UserReferral::TOKENS_ON_INVITE
        end

        created_referrals << referral
      else
        errors << referral.errors.full_messages.first
      end
    end

    if created_referrals.any?
      render json: {
        success: true,
        message: "#{created_referrals.count} invitation(s) sent!",
        tokens_earned: tokens_earned,
        referrals_count: created_referrals.count,
        errors: errors
      }
    else
      render json: { error: errors.first || "Failed to send invitations" }, status: :unprocessable_entity
    end
  end

  def index
    @referrals = current_user.sent_referrals.order(created_at: :desc)
    @stats = {
      total: @referrals.count,
      pending: @referrals.pending.count,
      signed_up: @referrals.signed_up.count,
      tokens_earned: @referrals.sum(:tokens_awarded) + (@referrals.count * UserReferral::TOKENS_ON_INVITE),
      remaining_slots: [UserReferral::MAX_REFERRALS - @referrals.count, 0].max
    }
  end
end
