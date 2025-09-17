class ContactMailer < ApplicationMailer
  DEFAULT_TO = 'lydia@cruxmarketing.ai'

  def contact_request
    @name = params[:name]
    @email = params[:email]
    @subject_line = params[:subject].presence || 'New website contact'
    @message = params[:message]

    recipient = params[:to].presence || DEFAULT_TO
    mail(to: recipient, subject: "Contact: #{@subject_line}", reply_to: @email)
  end
end


