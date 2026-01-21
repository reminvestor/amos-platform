# frozen_string_literal: true

module Api
  class ModuleWebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!
    before_action :find_webhook

    # POST /api/webhooks/modules/:slug
    def receive
      Rails.logger.info "[ModuleWebhook] Received webhook: #{@webhook.event_name}"

      # Verify authentication
      unless @webhook.verify_request(request)
        Rails.logger.warn "[ModuleWebhook] Authentication failed for: #{@webhook.slug}"
        return render json: { error: 'Unauthorized' }, status: :unauthorized
      end

      # Parse payload
      payload = parse_payload
      return render json: { error: 'Invalid payload' }, status: :bad_request unless payload

      # Trigger the webhook
      result = @webhook.trigger!(payload, request)

      if result[:success]
        render json: {
          success: true,
          message: 'Webhook processed successfully',
          execution_id: result[:execution_id]
        }
      else
        render json: {
          success: false,
          error: result[:error] || result[:errors]&.join(', ')
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "[ModuleWebhook] Error processing webhook: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      render json: { error: 'Internal server error' }, status: :internal_server_error
    end

    private

    def find_webhook
      @webhook = ModuleWebhook.find_by!(slug: params[:slug])
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Webhook not found' }, status: :not_found
    end

    def parse_payload
      case request.content_type
      when 'application/json'
        JSON.parse(request.raw_post)
      when 'application/x-www-form-urlencoded'
        params.to_unsafe_h.except(:controller, :action, :slug)
      else
        JSON.parse(request.raw_post) rescue nil
      end
    rescue JSON::ParserError
      nil
    end
  end
end





