# frozen_string_literal: true

class OtpMailer < ApplicationMailer
  def send_otp(user, code)
    @user = user
    @code = code
    @expiry_minutes = 5

    mail(
      to: @user.email,
      subject: "Your AMOS Labs verification code: #{@code}"
    )
  end
end
