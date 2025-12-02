class ApplicationMailer < ActionMailer::Base
  include Rails.application.routes.url_helpers
  
  default from: ENV["MAILER_SENDER"] || "noreply@amoslabs.com"
  layout "mailer"
  
  # Set default URL options for mailers
  def default_url_options
    { host: ENV.fetch('APP_HOST', 'localhost:3000') }
  end
end
