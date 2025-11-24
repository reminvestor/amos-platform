class ApplicationMailer < ActionMailer::Base
  default from: ENV["MAILER_SENDER"] || "noreply@amoslabs.com"
  layout "mailer"
end
