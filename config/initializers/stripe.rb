Rails.application.config.to_prepare do
  Stripe.api_key = ENV['STRIPE_SECRET_KEY']
  Stripe.api_version = '2024-12-18.acacia' # Use the latest stable API version
end
