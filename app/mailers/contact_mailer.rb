class ContactMailer < ApplicationMailer
  default to: 'lydia@cruxmarketing.ai'

  def contact_request
    @name = params[:name]
    @email = params[:email]
    @subject_line = params[:subject].presence || 'New website contact'
    @message = params[:message]

    mail(subject: "Contact: #{@subject_line}", reply_to: @email)
  end
end


