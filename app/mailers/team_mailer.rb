# frozen_string_literal: true

class TeamMailer < ApplicationMailer
  def invite_email(invite)
    @invite = invite
    @entity = invite.entity
    @inviter = invite.invited_by
    @accept_url = accept_team_invite_url(token: invite.token)
    
    mail(
      to: invite.email,
      subject: "You've been invited to join #{@entity.name} on AMOS"
    )
  end
end
