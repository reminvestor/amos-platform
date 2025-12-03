class ApplicationMailer < ActionMailer::Base
  include Rails.application.routes.url_helpers
  
  default from: ENV["MAILER_SENDER"] || "noreply@amoslabs.com"
  layout "mailer"
  
  # Set default URL options for mailers
  # Uses APPLICATION_HOST (set in Terraform) or falls back to APP_HOST or localhost
  def default_url_options
    host = ENV['APPLICATION_HOST'] || ENV['APP_HOST'] || 'localhost:3000'
    # Ensure we have a proper URL with protocol
    if host.start_with?('http')
      uri = URI.parse(host)
      { host: uri.host, protocol: uri.scheme }
    else
      { host: host, protocol: 'https' }
    end
  end
end
