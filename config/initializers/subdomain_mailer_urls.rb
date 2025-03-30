# Set up mailer URLs to work properly with subdomains
Rails.application.configure do
  # Helper method to construct the full host for tracking URLs
  config.after_initialize do
    if Rails.env.production?
      # Handle tracking URLs for open/click tracking
      subdomain_host = "app.#{ENV['APPLICATION_HOST'] || 'everloom.ai'}"
      
      # Override default_url_options for routes used in mailers
      Rails.application.routes.default_url_options[:host] = subdomain_host
      Rails.application.routes.default_url_options[:protocol] = 'https'
      
      # Set specific route helpers for tracking-related URLs
      email_open_url_helper = Rails.application.routes.url_helpers.method(:email_open_url)
      email_click_url_helper = Rails.application.routes.url_helpers.method(:email_click_url)
      
      # Override the email_open_url method to always use the app subdomain
      Rails.application.routes.url_helpers.define_singleton_method(:email_open_url) do |*args, **kwargs|
        kwargs[:host] = subdomain_host unless kwargs.key?(:host)
        kwargs[:protocol] = 'https' unless kwargs.key?(:protocol)
        email_open_url_helper.call(*args, **kwargs)
      end
      
      # Override the email_click_url method to always use the app subdomain
      Rails.application.routes.url_helpers.define_singleton_method(:email_click_url) do |*args, **kwargs|
        kwargs[:host] = subdomain_host unless kwargs.key?(:host)
        kwargs[:protocol] = 'https' unless kwargs.key?(:protocol)
        email_click_url_helper.call(*args, **kwargs)
      end
    end
  end
end 