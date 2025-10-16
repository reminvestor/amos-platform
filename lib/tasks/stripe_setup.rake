namespace :stripe do
  desc "Create subscription products and prices in Stripe"
  task setup_products: :environment do
    require 'stripe'

    puts "Setting up Stripe products and prices..."
    puts "Using Stripe Secret Key: #{ENV['STRIPE_SECRET_KEY']&.slice(0, 20)}..."

    begin
      # Create Starter Plan
      puts "\n Creating Starter Plan..."
      starter_product = Stripe::Product.create(
        name: 'Starter Plan',
        description: 'For individuals and small teams - 10,000 emails/month, 200k AI credits'
      )

      starter_price = Stripe::Price.create(
        product: starter_product.id,
        unit_amount: 2900, # $29.00
        currency: 'usd',
        recurring: {
          interval: 'month'
        },
        lookup_key: 'starter'
      )

      puts "✅ Starter Plan created!"
      puts "   Product ID: #{starter_product.id}"
      puts "   Price ID: #{starter_price.id}"
      puts "   Add to .env: STRIPE_STARTER_PRICE_ID=#{starter_price.id}"

      # Create Professional Plan
      puts "\n📦 Creating Professional Plan..."
      pro_product = Stripe::Product.create(
        name: 'Professional Plan',
        description: 'For growing businesses and teams - 40,000 emails/month, 1M AI credits'
      )

      pro_price = Stripe::Price.create(
        product: pro_product.id,
        unit_amount: 11900, # $119.00
        currency: 'usd',
        recurring: {
          interval: 'month'
        },
        lookup_key: 'professional'
      )

      puts "✅ Professional Plan created!"
      puts "   Product ID: #{pro_product.id}"
      puts "   Price ID: #{pro_price.id}"
      puts "   Add to .env: STRIPE_PROFESSIONAL_PRICE_ID=#{pro_price.id}"

      # Create Business Plan
      puts "\n📦 Creating Business Plan..."
      business_product = Stripe::Product.create(
        name: 'Business Plan',
        description: 'For established teams - 100,000 emails/month, 2M AI credits'
      )

      business_price = Stripe::Price.create(
        product: business_product.id,
        unit_amount: 29900, # $299.00
        currency: 'usd',
        recurring: {
          interval: 'month'
        },
        lookup_key: 'business'
      )

      puts "✅ Business Plan created!"
      puts "   Product ID: #{business_product.id}"
      puts "   Price ID: #{business_price.id}"
      puts "   Add to .env: STRIPE_BUSINESS_PRICE_ID=#{business_price.id}"

      # Summary
      puts "\n" + "="*80
      puts "🎉 All products and prices created successfully!"
      puts "="*80
      puts "\nAdd these to your .env file:\n\n"
      puts "STRIPE_DEFAULT_PRICE_ID=#{starter_price.id}"
      puts "STRIPE_STARTER_PRICE_ID=#{starter_price.id}"
      puts "STRIPE_PROFESSIONAL_PRICE_ID=#{pro_price.id}"
      puts "STRIPE_BUSINESS_PRICE_ID=#{business_price.id}"
      puts "\n" + "="*80

    rescue Stripe::StripeError => e
      puts "\n❌ Error creating Stripe products: #{e.message}"
      puts "\nMake sure your STRIPE_SECRET_KEY is set correctly in .env"
    end
  end

  desc "List all Stripe products and prices"
  task list_products: :environment do
    require 'stripe'

    puts "Listing Stripe products and prices..."
    puts "="*80

    begin
      products = Stripe::Product.list(limit: 100)

      products.data.each do |product|
        puts "\n📦 Product: #{product.name}"
        puts "   ID: #{product.id}"
        puts "   Description: #{product.description}"

        prices = Stripe::Price.list(product: product.id)
        prices.data.each do |price|
          amount = price.unit_amount ? "$#{price.unit_amount / 100.0}" : "Free"
          interval = price.recurring ? "/#{price.recurring.interval}" : ""
          lookup_key = price.lookup_key ? " (#{price.lookup_key})" : ""

          puts "   💰 Price: #{amount}#{interval}#{lookup_key}"
          puts "      Price ID: #{price.id}"
        end
      end

      puts "\n" + "="*80

    rescue Stripe::StripeError => e
      puts "\n❌ Error listing Stripe products: #{e.message}"
    end
  end
end
