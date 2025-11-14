# Specialized agent for handling integrations (Stripe, etc.)
module AgentJobs
  class IntegrationAgentJob < BaseAgentJob
    
    def execute_agent_task
      Rails.logger.info "[IntegrationAgent] Processing: #{@task}"
      
      # Determine integration task type
      integration_type, action = analyze_integration_task
      
      case integration_type
      when :stripe
        handle_stripe_task(action)
      when :zapier
        handle_zapier_task(action)
      when :webhook
        handle_webhook_task(action)
      else
        handle_general_integration_task
      end
    end
    
    private
    
    def analyze_integration_task
      task_lower = @task.downcase
      
      if task_lower.include?('stripe')
        action = case task_lower
        when /import|sync|pull.*customers?/i
          :import_customers
        when /payment|charge|invoice/i
          :process_payment
        when /subscription/i
          :manage_subscription
        when /connect|setup/i
          :setup_connection
        else
          :general_stripe
        end
        [:stripe, action]
      elsif task_lower.include?('zapier')
        [:zapier, :setup_zap]
      elsif task_lower.include?('webhook')
        [:webhook, :configure_webhook]
      else
        [:unknown, :general]
      end
    end
    
    def handle_stripe_task(action)
      case action
      when :import_customers
        import_stripe_customers
      when :process_payment
        process_stripe_payment
      when :manage_subscription
        manage_stripe_subscription
      when :setup_connection
        setup_stripe_connection
      else
        handle_general_stripe_task
      end
    end
    
    def import_stripe_customers
      stream_content("I'll import your customers from Stripe.")
      
      # Check Stripe connection
      stripe_connection = check_stripe_connection
      unless stripe_connection
        return request_stripe_setup
      end
      
      update_status('running', 'Fetching customers from Stripe...', progress: 20)
      
      # Determine import scope
      import_scope = request_user_input(
        "Which customers should I import?",
        options: ["All customers", "Last 10 customers", "Customers from last 30 days", "Active subscribers only"]
      )
      
      # Fetch from Stripe
      customers = fetch_stripe_customers(stripe_connection, import_scope)
      
      update_status('running', "Processing #{customers.count} customers...", progress: 50)
      
      # Import customers as contacts
      imported = 0
      skipped = 0
      errors = []
      
      customers.each_with_index do |stripe_customer, index|
        begin
          result = import_stripe_customer(stripe_customer)
          if result[:created]
            imported += 1
          else
            skipped += 1
          end
          
          # Update progress
          progress = 50 + (40 * (index + 1) / customers.count)
          update_status('running', "Processing customer #{index + 1}/#{customers.count}...", progress: progress)
        rescue => e
          errors << { customer: stripe_customer.id, error: e.message }
        end
      end
      
      # Final report
      stream_content(
        "✅ Stripe import completed!\n\n" +
        "• Imported: #{imported} new contacts\n" +
        "• Skipped: #{skipped} existing contacts\n" +
        "• Errors: #{errors.count}\n\n" +
        "Your contact list has been updated."
      )
      
      {
        success: true,
        imported: imported,
        skipped: skipped,
        errors: errors,
        message: "Imported #{imported} customers from Stripe"
      }
    end
    
    def fetch_stripe_customers(connection, scope)
      stripe = initialize_stripe(connection)
      
      case scope
      when "All customers"
        stripe.customers.list(limit: 100).auto_paging_each.to_a
      when "Last 10 customers"
        stripe.customers.list(limit: 10).data
      when "Customers from last 30 days"
        stripe.customers.list(
          created: { gte: 30.days.ago.to_i },
          limit: 100
        ).auto_paging_each.to_a
      when "Active subscribers only"
        stripe.customers.list(limit: 100).auto_paging_each.select { |c|
          c.subscriptions.data.any? { |s| s.status == 'active' }
        }.to_a
      else
        []
      end
    end
    
    def import_stripe_customer(stripe_customer)
      entity = Entity.find(@context[:entity_id])
      
      # Check if contact already exists
      existing = Contact.find_by(
        entity: entity,
        email: stripe_customer.email
      )
      
      if existing
        # Update with Stripe data
        existing.update!(
          metadata: existing.metadata.merge(
            stripe_customer_id: stripe_customer.id,
            stripe_created: stripe_customer.created,
            stripe_subscriptions: stripe_customer.subscriptions.data.map(&:id)
          )
        )
        { created: false, contact: existing }
      else
        # Create new contact
        contact = Contact.create!(
          entity: entity,
          email: stripe_customer.email,
          first_name: stripe_customer.name&.split(' ')&.first,
          last_name: stripe_customer.name&.split(' ')&.last,
          phone: stripe_customer.phone,
          tags: ['stripe-customer'],
          metadata: {
            stripe_customer_id: stripe_customer.id,
            stripe_created: stripe_customer.created,
            stripe_subscriptions: stripe_customer.subscriptions.data.map(&:id),
            imported_from: 'stripe',
            imported_at: Time.current
          }
        )
        { created: true, contact: contact }
      end
    end
    
    def process_stripe_payment
      stream_content("I'll help you process a payment through Stripe.")
      
      # Check connection
      stripe_connection = check_stripe_connection
      unless stripe_connection
        return request_stripe_setup
      end
      
      # Gather payment details
      amount = request_user_input("What's the payment amount? (e.g., 99.99)")
      description = request_user_input("What's this payment for?")
      customer_email = request_user_input("Customer email address:")
      
      # Find or create Stripe customer
      stripe = initialize_stripe(stripe_connection)
      customer = find_or_create_stripe_customer(stripe, customer_email)
      
      # Create payment intent
      update_status('running', 'Creating payment...', progress: 50)
      
      payment_intent = stripe.payment_intents.create(
        amount: (amount.to_f * 100).to_i, # Convert to cents
        currency: 'usd',
        customer: customer.id,
        description: description,
        metadata: {
          entity_id: @context[:entity_id],
          created_by: 'amos_agent'
        }
      )
      
      stream_content(
        "✅ Payment created!\n\n" +
        "Amount: $#{amount}\n" +
        "Customer: #{customer_email}\n" +
        "Status: Awaiting payment\n\n" +
        "Send this link to the customer to complete payment:\n" +
        "#{generate_payment_link(payment_intent)}"
      )
      
      {
        success: true,
        payment_intent_id: payment_intent.id,
        amount: amount,
        message: "Payment of $#{amount} created for #{customer_email}"
      }
    end
    
    def manage_stripe_subscription
      stream_content("I'll help you manage Stripe subscriptions.")
      
      stripe_connection = check_stripe_connection
      unless stripe_connection
        return request_stripe_setup
      end
      
      action = request_user_input(
        "What would you like to do?",
        options: ["View subscriptions", "Create subscription", "Cancel subscription", "Update subscription"]
      )
      
      case action
      when "View subscriptions"
        view_stripe_subscriptions(stripe_connection)
      when "Create subscription"
        create_stripe_subscription(stripe_connection)
      when "Cancel subscription"
        cancel_stripe_subscription(stripe_connection)
      when "Update subscription"
        update_stripe_subscription(stripe_connection)
      end
    end
    
    def view_stripe_subscriptions(connection)
      stripe = initialize_stripe(connection)
      subscriptions = stripe.subscriptions.list(limit: 20).data
      
      if subscriptions.empty?
        stream_content("No active subscriptions found.")
        return { success: true, subscriptions: [] }
      end
      
      message = "📊 Active Subscriptions:\n\n"
      subscriptions.each do |sub|
        customer = stripe.customers.retrieve(sub.customer)
        message += "• Customer: #{customer.email}\n"
        message += "  Plan: #{sub.items.data.first.price.nickname || sub.items.data.first.price.id}\n"
        message += "  Amount: $#{sub.items.data.first.price.unit_amount / 100.0}/#{sub.items.data.first.price.recurring.interval}\n"
        message += "  Status: #{sub.status}\n\n"
      end
      
      stream_content(message)
      
      {
        success: true,
        subscriptions: subscriptions.map { |s| s.id }
      }
    end
    
    def handle_zapier_task(action)
      stream_content("I'll help you set up a Zapier integration.")
      
      webhook_url = generate_webhook_url
      
      stream_content(
        "To connect with Zapier:\n\n" +
        "1. Create a new Zap in Zapier\n" +
        "2. Choose 'Webhooks by Zapier' as the trigger\n" +
        "3. Select 'Catch Hook' as the trigger event\n" +
        "4. Use this webhook URL:\n\n" +
        "#{webhook_url}\n\n" +
        "5. Test the webhook and map your fields\n" +
        "6. Choose your action app and configure it\n\n" +
        "Common use cases:\n" +
        "• New contact → Add to email list\n" +
        "• Form submission → Create contact\n" +
        "• Payment received → Update customer"
      )
      
      # Store webhook configuration
      Webhook.create!(
        entity_id: @context[:entity_id],
        url: webhook_url,
        events: ['all'],
        status: 'active',
        metadata: { integration: 'zapier' }
      )
      
      {
        success: true,
        webhook_url: webhook_url,
        message: "Zapier webhook created successfully"
      }
    end
    
    def check_stripe_connection
      entity = Entity.find(@context[:entity_id])
      connection = entity.connections.joins(:integration).find_by(integrations: { slug: 'stripe' })
      
      if connection && connection.active?
        connection
      else
        nil
      end
    end
    
    def request_stripe_setup
      stream_content(
        "❌ Stripe is not connected yet.\n\n" +
        "To connect Stripe:\n" +
        "1. Go to Settings → Integrations\n" +
        "2. Click on Stripe\n" +
        "3. Enter your Stripe API key\n" +
        "4. Save the connection\n\n" +
        "Then try this task again."
      )
      
      {
        success: false,
        message: "Stripe not connected. Please set up Stripe integration first."
      }
    end
    
    def initialize_stripe(connection)
      require 'stripe'
      Stripe.api_key = connection.credentials.api_key
      Stripe
    end
    
    def find_or_create_stripe_customer(stripe, email)
      # Search for existing customer
      existing = stripe.customers.list(email: email, limit: 1).data.first
      
      if existing
        existing
      else
        # Create new customer
        stripe.customers.create(
          email: email,
          metadata: {
            entity_id: @context[:entity_id],
            created_by: 'amos_agent'
          }
        )
      end
    end
    
    def generate_payment_link(payment_intent)
      # In production, this would generate a hosted payment page
      "https://checkout.stripe.com/pay/#{payment_intent.id}"
    end
    
    def generate_webhook_url
      # Generate unique webhook endpoint
      webhook_id = SecureRandom.hex(16)
      "#{Rails.application.config.app_url}/webhooks/#{webhook_id}"
    end
    
    def handle_general_integration_task
      stream_content(
        "I can help you with various integrations:\n\n" +
        "**Stripe**\n" +
        "• Import customers\n" +
        "• Process payments\n" +
        "• Manage subscriptions\n\n" +
        "**Zapier**\n" +
        "• Set up webhooks\n" +
        "• Connect to 5000+ apps\n\n" +
        "**Other Integrations**\n" +
        "• Email services (SendGrid, Mailgun)\n" +
        "• Analytics (Google Analytics, Mixpanel)\n" +
        "• CRM systems\n\n" +
        "What integration would you like to work with?"
      )
      
      {
        success: true,
        message: "Please specify which integration you'd like to use."
      }
    end
  end
end

