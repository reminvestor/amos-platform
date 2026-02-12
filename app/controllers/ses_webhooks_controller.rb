# app/controllers/ses_webhooks_controller.rb
class SesWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!, if: -> { request.format.json? }

  # Verify SNS signature before processing (Story 0.6)
  before_action :verify_sns_signature!

  def create
    message = JSON.parse(request.body.read)

    case message['Type']
    when 'SubscriptionConfirmation'
      handle_subscription_confirmation(message)
    when 'Notification'
      handle_notification(message)
    when 'UnsubscribeConfirmation'
      handle_unsubscribe_confirmation(message)
    else
      render json: { error: 'Unknown message type' }, status: :bad_request
    end
  end

  private

  def verify_sns_signature!
    # Get raw request body (before Rails parses it)
    request.body.rewind
    raw_body = request.body.read
    request.body.rewind

    AwsSnsSignatureValidator.verify!(raw_body, request.headers)
  rescue AwsSnsSignatureValidator::InvalidSignatureError => e
    Rails.logger.error "SNS signature verification failed: #{e.message}"
    render json: { error: 'Invalid signature' }, status: :forbidden
  rescue AwsSnsSignatureValidator::InvalidMessageError => e
    Rails.logger.error "Invalid SNS message: #{e.message}"
    render json: { error: 'Invalid message' }, status: :bad_request
  rescue AwsSnsSignatureValidator::InvalidCertificateError => e
    Rails.logger.error "Invalid SNS certificate: #{e.message}"
    render json: { error: 'Invalid certificate' }, status: :forbidden
  end

  def handle_subscription_confirmation(message)
    # CRITICAL: Only confirm after signature verification
    subscribe_url = message['SubscribeURL']

    # Confirm subscription
    response = Faraday.get(subscribe_url) do |req|
      req.options.timeout = 10
    end

    if response.success?
      Rails.logger.info "SNS subscription confirmed: #{message['TopicArn']}"
      render json: { status: 'subscription confirmed' }, status: :ok
    else
      Rails.logger.error "Failed to confirm SNS subscription: #{response.status}"
      render json: { error: 'Subscription confirmation failed' }, status: :internal_server_error
    end
  end

  def handle_notification(message)
    # Parse nested SES message
    ses_message = JSON.parse(message['Message'])

    # Process the SES event
    SesEventService.new.process_event(ses_message)

    render json: { status: 'processed' }, status: :ok
  end

  def handle_unsubscribe_confirmation(message)
    Rails.logger.info "SNS unsubscribe confirmed: #{message['TopicArn']}"
    render json: { status: 'unsubscribe confirmed' }, status: :ok
  end
end

