# Fix for SSL issues on Heroku with custom domains
Rails.application.config.after_initialize do
  # Add special handling for GoDaddy DNS with Heroku
  unless Rails.env.development?
    # Explicitly set the host for URL generation
    Rails.application.routes.default_url_options[:host] = ENV['APPLICATION_HOST'] || 'app.amoslabs.com'
    Rails.application.routes.default_url_options[:protocol] = 'https'

    # Force all requests to be treated as secure
    Rails.application.configure do
      config.action_dispatch.default_headers.merge!({
        'X-Frame-Options' => 'SAMEORIGIN',
        'X-XSS-Protection' => '1; mode=block',
        'X-Content-Type-Options' => 'nosniff',
        'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains'
      })
    end
  end
end 