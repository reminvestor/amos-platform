class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_webhook_signature

  def receive
    # Find integration by slug
    integration = Integration.find_by!(slug: params[:integration_slug])

    # Process webhook based on integration type
    case integration.slug
    when "stripe"
      process_stripe_webhook
    when "shopify"
      process_shopify_webhook
    when "hubspot"
      process_hubspot_webhook
    when "quickbooks"
      process_quickbooks_webhook
    else
      process_generic_webhook(integration)
    end

    head :ok
  rescue => e
    Rails.logger.error "Webhook processing error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    head :bad_request
  end

  private

  def verify_webhook_signature
    # Each integration has its own signature verification
    case params[:integration_slug]
    when "stripe"
      verify_stripe_signature
    when "shopify"
      verify_shopify_signature
    when "hubspot"
      verify_hubspot_signature
    else
      # Generic signature verification if needed
      true
    end
  end

  def verify_stripe_signature
    payload = request.body.read
    sig_header = request.headers["Stripe-Signature"]
    endpoint_secret = ENV["STRIPE_WEBHOOK_SECRET"]

    return true if endpoint_secret.blank? # Skip in development

    begin
      Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
      true
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Rails.logger.error "Stripe webhook verification failed: #{e.message}"
      head :bad_request and return false
    end
  end

  def verify_shopify_signature
    # Shopify uses HMAC-SHA256
    data = request.body.read
    hmac_header = request.headers["X-Shopify-Hmac-Sha256"]
    webhook_secret = ENV["SHOPIFY_WEBHOOK_SECRET"]

    return true if webhook_secret.blank?

    calculated_hmac = Base64.strict_encode64(
      OpenSSL::HMAC.digest("sha256", webhook_secret, data)
    )

    unless ActiveSupport::SecurityUtils.secure_compare(calculated_hmac, hmac_header.to_s)
      head :unauthorized and return false
    end

    true
  end

  def verify_hubspot_signature
    # HubSpot v3 uses SHA256
    source = request.headers["X-HubSpot-Signature-v3"]
    return true if source.blank?

    client_secret = ENV["HUBSPOT_CLIENT_SECRET"]
    return true if client_secret.blank?

    source_string = "POST#{request.url}#{request.body.read}"
    hash = OpenSSL::HMAC.hexdigest("sha256", client_secret, source_string)

    unless ActiveSupport::SecurityUtils.secure_compare(hash, source)
      head :unauthorized and return false
    end

    true
  end

  def process_stripe_webhook
    event = JSON.parse(request.body.read)

    # Handle affiliate commission events first
    handle_affiliate_commission_events(event)

    # Find connections for this Stripe account
    stripe_account_id = event.dig("account")
    connections = find_connections_for_webhook("stripe", stripe_account_id)

    # Create scout message for processing + fire automations
    connections.each do |connection|
      ScoutMessage.create!(
        user_id: connection.entity.users.first.id,
        entity_id: connection.entity_id,
        role: "webhook",
        content: "Stripe webhook received: #{event['type']}",
        metadata: {
          webhook_source: "stripe",
          event_type: event["type"],
          event_id: event["id"],
          payload: event
        }
      )

      # Fire matching automations via AutomationBridge
      fire_webhook_automations(connection.entity, "stripe", event)
    end
  end

  # Handle affiliate commission creation based on Stripe events
  def handle_affiliate_commission_events(event)
    case event['type']
    when 'checkout.session.completed'
      handle_checkout_completed(event)
    when 'invoice.payment_succeeded'
      handle_invoice_payment(event)
    end
  rescue => e
    Rails.logger.error "Affiliate commission processing error: #{e.message}"
    # Don't fail the entire webhook if commission processing fails
  end

  # Handle Stripe checkout completion - first payment
  def handle_checkout_completed(event)
    session = event['data']['object']
    customer_id = session['customer']

    return unless customer_id

    # Find entity by Stripe customer ID
    entity = Entity.find_by(stripe_customer_id: customer_id)
    return unless entity

    # Get amount (in cents, convert to dollars)
    amount = session['amount_total'] ? session['amount_total'] / 100.0 : 0

    return if amount.zero?

    # Create affiliate commission for first payment
    AffiliateCommissionService.create_for_first_payment(
      entity,
      amount,
      stripe_event_id: event['id']
    )

    Rails.logger.info "Processed checkout.session.completed for entity #{entity.id}"
  rescue => e
    Rails.logger.error "Error handling checkout completion: #{e.message}"
  end

  # Handle Stripe invoice payment - recurring payments
  def handle_invoice_payment(event)
    invoice = event['data']['object']
    customer_id = invoice['customer']

    return unless customer_id

    # Skip if this is the first invoice (handled by checkout.session.completed)
    return if invoice['billing_reason'] == 'subscription_create'

    # Find entity by Stripe customer ID
    entity = Entity.find_by(stripe_customer_id: customer_id)
    return unless entity

    # Get amount (in cents, convert to dollars)
    amount = invoice['amount_paid'] ? invoice['amount_paid'] / 100.0 : 0

    return if amount.zero?

    # Create recurring commission if within 12 months
    AffiliateCommissionService.create_for_recurring_payment(
      entity,
      amount,
      stripe_event_id: event['id']
    )

    Rails.logger.info "Processed invoice.payment_succeeded for entity #{entity.id}"
  rescue => e
    Rails.logger.error "Error handling invoice payment: #{e.message}"
  end

  def process_shopify_webhook
    topic = request.headers["X-Shopify-Topic"]
    shop_domain = request.headers["X-Shopify-Shop-Domain"]
    payload = JSON.parse(request.body.read)

    connections = find_connections_for_webhook("shopify", shop_domain)

    connections.each do |connection|
      ScoutMessage.create!(
        user_id: connection.entity.users.first.id,
        entity_id: connection.entity_id,
        role: "webhook",
        content: "Shopify webhook received: #{topic}",
        metadata: {
          webhook_source: "shopify",
          event_type: topic,
          shop_domain: shop_domain,
          payload: payload
        }
      )

      # Fire matching automations
      fire_webhook_automations(connection.entity, "shopify", { "type" => topic, "data" => { "object" => payload } })
    end
  end

  def process_hubspot_webhook
    events = JSON.parse(request.body.read)

    # HubSpot sends arrays of events
    events.each do |event|
      portal_id = event["portalId"]
      connections = find_connections_for_webhook("hubspot", portal_id)

      connections.each do |connection|
        ScoutMessage.create!(
          user_id: connection.entity.users.first.id,
          entity_id: connection.entity_id,
          role: "webhook",
          content: "HubSpot webhook received: #{event['subscriptionType']}",
          metadata: {
            webhook_source: "hubspot",
            event_type: event["subscriptionType"],
            portal_id: portal_id,
            payload: event
          }
        )

        # Fire matching automations
        fire_webhook_automations(connection.entity, "hubspot", { "type" => event["subscriptionType"], "data" => { "object" => event } })
      end
    end
  end

  def process_quickbooks_webhook
    payload = JSON.parse(request.body.read)

    payload["eventNotifications"].each do |notification|
      realm_id = notification["realmId"]
      connections = find_connections_for_webhook("quickbooks", realm_id)

      connections.each do |connection|
        notification["dataChangeEvent"]["entities"].each do |entity|
          ScoutMessage.create!(
            user_id: connection.entity.users.first.id,
            entity_id: connection.entity_id,
            role: "webhook",
            content: "QuickBooks webhook: #{entity['name']} #{entity['operation']}",
            metadata: {
              webhook_source: "quickbooks",
              event_type: "#{entity['name']}.#{entity['operation']}",
              realm_id: realm_id,
              entity_id: entity["id"],
              payload: entity
            }
          )
        end
      end
    end
  end

  def process_generic_webhook(integration)
    payload = JSON.parse(request.body.read) rescue request.body.read

    # For generic webhooks, process all active connections
    connections = Connection.active.where(integration: integration)

    connections.each do |connection|
      ScoutMessage.create!(
        user_id: connection.entity.users.first.id,
        entity_id: connection.entity_id,
        role: "webhook",
        content: "#{integration.name} webhook received",
        metadata: {
          webhook_source: integration.slug,
          payload: payload,
          headers: request.headers.to_h.select { |k, _| k.start_with?("HTTP_") }
        }
      )
    end
  end

  def find_connections_for_webhook(integration_slug, account_identifier)
    # Find connections that match the webhook source
    integration = Integration.find_by!(slug: integration_slug)

    # Look for connections with matching account ID in metadata
    Connection.active
              .where(integration: integration)
              .where("metadata->>'account_id' = ? OR metadata->>'shop_domain' = ? OR metadata->>'portal_id' = ? OR metadata->>'realm_id' = ?",
                     account_identifier.to_s, account_identifier.to_s, account_identifier.to_s, account_identifier.to_s)
  end

  # Fire automations that match this webhook event via AutomationBridge
  # This unifies integrations with automations: a Stripe webhook event
  # fires any automation with trigger_type=webhook that matches the event.
  def fire_webhook_automations(entity, integration_slug, event)
    event_type = event["type"].to_s
    webhook_path = "#{integration_slug}/#{event_type}"

    # Build payload for AutomationBridge
    payload = {
      integration: integration_slug,
      event_type: event_type,
      event_id: event["id"],
      data: event.dig("data", "object") || event["data"] || event
    }

    # Fire through AutomationBridge's webhook handler
    Modules::AutomationBridge.on_webhook(payload, entity, webhook_path)

    Rails.logger.info "[Webhooks] Fired automations for #{webhook_path} on entity #{entity.id}"
  rescue => e
    Rails.logger.error "[Webhooks] Failed to fire automations for #{integration_slug}: #{e.message}"
    # Don't fail the webhook if automation firing fails
  end
end
