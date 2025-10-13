namespace :stripe do
  desc "List all webhook endpoints configured in Stripe"
  task list_webhooks: :environment do
    require 'stripe'

    puts "Fetching webhook endpoints from Stripe..."
    puts "="*80

    begin
      endpoints = Stripe::WebhookEndpoint.list(limit: 100)

      if endpoints.data.empty?
        puts "\n❌ No webhook endpoints configured in Stripe"
        puts "\nTo add a webhook endpoint:"
        puts "1. Go to: https://dashboard.stripe.com/webhooks"
        puts "2. Click 'Add endpoint'"
        puts "3. URL: https://yourdomain.com/stripe/webhooks"
        puts "4. Select these events:"
        puts "   - customer.subscription.created"
        puts "   - customer.subscription.updated"
        puts "   - customer.subscription.deleted"
        puts "   - invoice.payment_succeeded"
        puts "   - invoice.payment_failed"
        puts "   - customer.subscription.trial_will_end"
      else
        endpoints.data.each_with_index do |endpoint, index|
          puts "\n📍 Endpoint ##{index + 1}"
          puts "   ID: #{endpoint.id}"
          puts "   URL: #{endpoint.url}"
          puts "   Status: #{endpoint.status}"
          puts "   Events listening for:"

          if endpoint.enabled_events.include?('*')
            puts "   - ALL EVENTS (*)"
          else
            endpoint.enabled_events.each do |event|
              puts "   - #{event}"
            end
          end

          puts "   Created: #{Time.at(endpoint.created).strftime('%B %d, %Y')}"
        end
      end

      puts "\n" + "="*80

    rescue Stripe::StripeError => e
      puts "\n❌ Error fetching webhook endpoints: #{e.message}"
      puts "\nMake sure your STRIPE_SECRET_KEY is set correctly in .env"
    end
  end

  desc "Create a webhook endpoint in Stripe for production"
  task :create_webhook, [:url] => :environment do |t, args|
    require 'stripe'

    url = args[:url]

    if url.blank?
      puts "❌ Error: URL is required"
      puts "\nUsage:"
      puts "  rails stripe:create_webhook[https://yourdomain.com/stripe/webhooks]"
      exit 1
    end

    unless url.start_with?('https://')
      puts "❌ Error: URL must use HTTPS"
      exit 1
    end

    puts "Creating webhook endpoint..."
    puts "URL: #{url}"

    begin
      endpoint = Stripe::WebhookEndpoint.create(
        url: url,
        enabled_events: [
          'customer.subscription.created',
          'customer.subscription.updated',
          'customer.subscription.deleted',
          'invoice.payment_succeeded',
          'invoice.payment_failed',
          'customer.subscription.trial_will_end'
        ],
        api_version: '2024-12-18.acacia'
      )

      puts "\n✅ Webhook endpoint created successfully!"
      puts "="*80
      puts "Endpoint ID: #{endpoint.id}"
      puts "URL: #{endpoint.url}"
      puts "Status: #{endpoint.status}"
      puts "\nSigning Secret (add to .env):"
      puts "STRIPE_WEBHOOK_SECRET=#{endpoint.secret}"
      puts "="*80

    rescue Stripe::StripeError => e
      puts "\n❌ Error creating webhook endpoint: #{e.message}"
    end
  end

  desc "Test webhook endpoint by sending a test event"
  task test_webhook: :environment do
    require 'stripe'

    puts "Testing webhook endpoint..."
    puts "This will trigger a test event to your webhook URL"
    puts "="*80

    begin
      # Get the first webhook endpoint
      endpoints = Stripe::WebhookEndpoint.list(limit: 1)

      if endpoints.data.empty?
        puts "❌ No webhook endpoints configured"
        puts "Run: rails stripe:create_webhook[https://yourdomain.com/stripe/webhooks]"
        exit 1
      end

      endpoint = endpoints.data.first
      puts "Testing endpoint: #{endpoint.url}"

      # This only works with Stripe CLI
      puts "\n⚠️  Note: To test webhooks, use Stripe CLI:"
      puts "  stripe trigger customer.subscription.created"
      puts "  stripe trigger invoice.payment_succeeded"
      puts "  stripe trigger customer.subscription.trial_will_end"

    rescue Stripe::StripeError => e
      puts "\n❌ Error: #{e.message}"
    end
  end

  desc "Show recommended events for AMOS subscription billing"
  task recommended_events: :environment do
    puts "Recommended Stripe Events for AMOS"
    puts "="*80
    puts "\n✅ REQUIRED EVENTS:\n\n"

    events = {
      'customer.subscription.created' => 'When a new subscription is created - saves subscription details',
      'customer.subscription.updated' => 'When subscription changes (plan upgrade/downgrade)',
      'customer.subscription.deleted' => 'When subscription is cancelled - marks as cancelled',
      'invoice.payment_succeeded' => 'When payment succeeds - resets token usage for new period',
      'invoice.payment_failed' => 'When payment fails - marks account as past_due',
      'customer.subscription.trial_will_end' => 'Three days before trial ends - send reminder email'
    }

    events.each do |event, description|
      puts "📌 #{event}"
      puts "   #{description}\n\n"
    end

    puts "="*80
    puts "\nTo configure in Stripe Dashboard:"
    puts "1. Go to: https://dashboard.stripe.com/webhooks"
    puts "2. Click 'Add endpoint'"
    puts "3. URL: https://yourdomain.com/stripe/webhooks"
    puts "4. Select the events listed above"
    puts "5. Copy the signing secret to your .env file"
  end

  desc "Verify webhook secret is configured"
  task verify_webhook_secret: :environment do
    secret = ENV['STRIPE_WEBHOOK_SECRET']

    puts "Checking webhook secret configuration..."
    puts "="*80

    if secret.blank?
      puts "❌ STRIPE_WEBHOOK_SECRET is not set in .env"
      puts "\nFor local development:"
      puts "  Run: stripe listen --forward-to http://localhost:3000/stripe/webhooks"
      puts "  Copy the whsec_... secret to your .env"
      puts "\nFor production:"
      puts "  1. Configure webhook in Stripe Dashboard"
      puts "  2. Copy the signing secret to your .env"
    elsif secret.start_with?('whsec_')
      puts "✅ Webhook secret is configured"
      puts "   Secret: #{secret[0..15]}..." # Show first 15 chars only
    else
      puts "⚠️  Webhook secret format looks incorrect"
      puts "   Expected to start with: whsec_"
      puts "   Current value: #{secret[0..15]}..."
    end

    puts "="*80
  end
end
