# frozen_string_literal: true

module Webhooks
  # WorkflowsController handles incoming webhooks that trigger workflows
  #
  # Webhook URL format: /webhooks/workflow/:webhook_path
  #
  # Example:
  #   POST /webhooks/workflow/my-workflow-abc123
  #   Content-Type: application/json
  #   X-Webhook-Signature: hmac_signature (optional)
  #
  #   { "event": "form_submitted", "data": { ... } }
  #
  class WorkflowsController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!, raise: false

    # POST /webhooks/workflow/:path
    def receive
      webhook_path = params[:path]

      # Find the trigger
      trigger = WorkflowTrigger.webhooks.find_by(webhook_path: webhook_path)

      unless trigger
        Rails.logger.warn "[WorkflowWebhook] Unknown webhook path: #{webhook_path}"
        return render json: { success: false, error: 'Webhook not found' }, status: :not_found
      end

      unless trigger.active?
        Rails.logger.warn "[WorkflowWebhook] Inactive webhook: #{webhook_path}"
        return render json: { success: false, error: 'Webhook is not active' }, status: :gone
      end

      # Verify signature if required
      if trigger.webhook_secret.present?
        signature = request.headers['X-Webhook-Signature'] || 
                    request.headers['X-Hub-Signature-256'] ||
                    request.headers['X-Signature']

        unless trigger.verify_webhook_signature(request.raw_post, signature)
          Rails.logger.warn "[WorkflowWebhook] Invalid signature for: #{webhook_path}"
          return render json: { success: false, error: 'Invalid signature' }, status: :unauthorized
        end
      end

      # Parse the payload
      payload = if request.content_type&.include?('json')
        JSON.parse(request.raw_post) rescue {}
      else
        params.to_unsafe_h.except(:path, :controller, :action)
      end

      # Fire the trigger
      result = trigger.fire!({
        payload: payload,
        headers: extract_headers,
        webhook_path: webhook_path,
        received_at: Time.current.iso8601
      })

      if result[:success]
        Rails.logger.info "[WorkflowWebhook] Triggered workflow for: #{webhook_path}, execution: #{result[:execution_id]}"
        render json: {
          success: true,
          execution_id: result[:execution_id],
          message: 'Workflow triggered'
        }
      else
        Rails.logger.error "[WorkflowWebhook] Failed to trigger: #{result[:error]}"
        render json: {
          success: false,
          error: result[:error]
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "[WorkflowWebhook] Error: #{e.message}"
      render json: { success: false, error: 'Internal error' }, status: :internal_server_error
    end

    private

    def extract_headers
      relevant_headers = %w[
        Content-Type User-Agent X-Request-Id X-Correlation-Id
        X-Forwarded-For X-Real-Ip
      ]

      headers = {}
      relevant_headers.each do |header|
        key = header.gsub('-', '_').upcase
        value = request.headers[header] || request.headers["HTTP_#{key}"]
        headers[header] = value if value.present?
      end
      headers
    end
  end
end
