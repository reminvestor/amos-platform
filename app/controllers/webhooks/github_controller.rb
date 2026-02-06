# frozen_string_literal: true

module Webhooks
  # GitHubController - Receives and processes GitHub webhook events
  #
  # Handles:
  # - pull_request: opened, closed, merged, review_requested
  # - pull_request_review: submitted (approved, changes_requested)
  # - check_run / check_suite: CI status updates
  # - issues: for bounty-linked issues
  #
  # Security: All payloads are verified via HMAC-SHA256 signature.
  #
  # Setup:
  #   1. In GitHub repo settings → Webhooks → Add webhook
  #   2. URL: https://app.amoslabs.com/webhooks/github
  #   3. Content type: application/json
  #   4. Secret: Set GITHUB_WEBHOOK_SECRET env var
  #   5. Events: Pull requests, Pull request reviews, Check runs
  #
  class GithubController < ApplicationController
    skip_before_action :authenticate_user!, raise: false
    skip_before_action :verify_authenticity_token

    before_action :verify_github_signature!

    # POST /webhooks/github
    def receive
      event_type = request.headers['X-GitHub-Event']
      delivery_id = request.headers['X-GitHub-Delivery']
      payload = JSON.parse(request.body.read)

      Rails.logger.info "[GitHub Webhook] Received #{event_type} (delivery: #{delivery_id})"

      # Process asynchronously to return 200 quickly
      GitHubWebhookJob.perform_later(event_type, payload, delivery_id)

      render json: { received: true, event: event_type }, status: :ok
    rescue JSON::ParserError => e
      Rails.logger.error "[GitHub Webhook] Invalid JSON: #{e.message}"
      render json: { error: 'Invalid JSON' }, status: :bad_request
    rescue => e
      Rails.logger.error "[GitHub Webhook] Error: #{e.message}"
      render json: { error: 'Processing error' }, status: :internal_server_error
    end

    private

    def verify_github_signature!
      secret = ENV['GITHUB_WEBHOOK_SECRET']

      # Skip verification in development if no secret configured
      if secret.blank?
        if Rails.env.development? || Rails.env.test?
          Rails.logger.debug "[GitHub Webhook] Skipping signature verification (no secret configured)"
          return
        else
          Rails.logger.error "[GitHub Webhook] GITHUB_WEBHOOK_SECRET not configured!"
          render json: { error: 'Webhook not configured' }, status: :service_unavailable
          return
        end
      end

      signature = request.headers['X-Hub-Signature-256']
      unless signature.present?
        Rails.logger.warn "[GitHub Webhook] Missing signature header"
        render json: { error: 'Missing signature' }, status: :unauthorized
        return
      end

      body = request.body.read
      request.body.rewind

      expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
      unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
        Rails.logger.warn "[GitHub Webhook] Invalid signature"
        render json: { error: 'Invalid signature' }, status: :unauthorized
      end
    end
  end
end
