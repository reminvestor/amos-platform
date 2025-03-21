class ApplicationMailer < ActionMailer::Base
  default from: ENV['AWS_SES_SENDER'] || "notifications@example.com"
  layout "mailer"
end
