class UserMailer < ApplicationMailer
  def admin_password_reset(user, temporary_password)
    @user = user
    @temporary_password = temporary_password
    @login_url = new_user_session_url
    
    mail(
      to: @user.email,
      subject: "Your password has been reset - Agent Marketing"
    )
  end
end
