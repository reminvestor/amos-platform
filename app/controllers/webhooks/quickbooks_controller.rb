# frozen_string_literal: true

module Webhooks
  class QuickbooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!, raise: false
    
    # POST /webhooks/quickbooks/disconnect
    # Called by QuickBooks when a user disconnects from Intuit's side
    def disconnect
      Rails.logger.info "📤 QuickBooks Disconnect Webhook received"
      Rails.logger.info "   Params: #{params.to_unsafe_h.except(:controller, :action).inspect}"
      
      # QuickBooks sends the realmId (company ID) in the webhook payload
      realm_id = params[:realmId] || params[:realm_id]
      
      if realm_id.blank?
        Rails.logger.warn "   ⚠️ No realmId provided in disconnect webhook"
        return head :ok
      end
      
      # Find connections with this realm_id in their credentials
      disconnected_count = 0
      
      Connection.joins(:integration).where(integrations: { slug: 'quickbooks' }).find_each do |connection|
        credentials = connection.integration_credentials.find_by(name: "OAuth Token")
        next unless credentials
        
        stored_realm_id = credentials.credentials&.dig("realmId") || 
                          credentials.credentials&.dig("realm_id")
        
        if stored_realm_id == realm_id
          Rails.logger.info "   🔌 Disconnecting connection #{connection.id} for realm #{realm_id}"
          
          connection.update!(
            status: :disconnected,
            last_error: "Disconnected via QuickBooks webhook at #{Time.current}"
          )
          
          # Optionally revoke the credentials
          credentials.update!(status: :revoked)
          
          disconnected_count += 1
        end
      end
      
      Rails.logger.info "   ✅ Disconnected #{disconnected_count} connection(s)"
      
      head :ok
    rescue => e
      Rails.logger.error "❌ QuickBooks disconnect webhook error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      head :ok # Return 200 to prevent retries
    end
    
    # POST /webhooks/quickbooks/notifications
    # General webhook endpoint for QuickBooks event notifications
    def notifications
      Rails.logger.info "📤 QuickBooks Notification Webhook received"
      
      # Verify the webhook signature if configured
      unless verify_webhook_signature
        Rails.logger.warn "   ⚠️ Invalid webhook signature"
        return head :unauthorized
      end
      
      # Process the webhook payload
      event_notifications = params[:eventNotifications] || []
      
      event_notifications.each do |notification|
        realm_id = notification[:realmId]
        data_change_event = notification[:dataChangeEvent]
        
        next unless data_change_event
        
        entities = data_change_event[:entities] || []
        entities.each do |entity|
          process_entity_change(realm_id, entity)
        end
      end
      
      head :ok
    rescue => e
      Rails.logger.error "❌ QuickBooks notification webhook error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      head :ok
    end
    
    private
    
    def verify_webhook_signature
      # QuickBooks webhook verification
      # The verifier token is set up in the QuickBooks developer portal
      verifier_token = Rails.application.credentials.dig(:quickbooks, :webhook_verifier_token)
      
      # If no verifier token configured, skip verification (development mode)
      return true if verifier_token.blank?
      
      # Get the signature from headers
      signature = request.headers["intuit-signature"]
      return false if signature.blank?
      
      # Calculate expected signature
      payload = request.raw_post
      expected_signature = Base64.strict_encode64(
        OpenSSL::HMAC.digest("SHA256", verifier_token, payload)
      )
      
      ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
    end
    
    def process_entity_change(realm_id, entity)
      entity_name = entity[:name]
      entity_id = entity[:id]
      operation = entity[:operation]
      
      Rails.logger.info "   📝 Entity change: #{entity_name} #{entity_id} - #{operation}"
      
      # You can add specific handling for different entity types here
      # For example, syncing customers, invoices, etc.
      case entity_name
      when "Customer"
        # Handle customer changes
      when "Invoice"
        # Handle invoice changes
      when "Payment"
        # Handle payment changes
      end
    end
  end
end

