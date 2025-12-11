class ReferralMailer < ApplicationMailer
  default from: 'AMOS <noreply@amoslabs.com>'

  def invite_email(referral)
    @referral = referral
    @referrer = referral.referrer
    @signup_url = new_user_registration_url(ref: referral.token)
    @free_tokens = 200_000  # Tokens new users get on signup

    mail(
      to: referral.referred_email,
      subject: "#{@referrer.full_name || @referrer.email.split('@').first} invited you to try AMOS - Get 200,000 Free AI Tokens!"
    )
  end
end
