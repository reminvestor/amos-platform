class ApplicationMailer < ActionMailer::Base
  default from: ENV["MAILGUN_FROM"] || "postmaster@#{ENV['MAILGUN_DOMAIN']}"
  layout "mailer"
end
