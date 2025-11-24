# app/controllers/ses_webhooks_controller.rb
class SesWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    # Handle SNS subscription confirmation
    if request.headers["x-amz-sns-message-type"] == "SubscriptionConfirmation"
      body = JSON.parse(request.body.read)
      # Confirm the subscription by visiting the SubscribeURL
      if body["SubscribeURL"]
        HTTParty.get(body["SubscribeURL"])
      end
      head :ok
      return
    end

    # Handle Notification
    if request.headers["x-amz-sns-message-type"] == "Notification"
      body = JSON.parse(request.body.read)
      SesEventService.new.process_event(body)
      head :ok
      return
    end

    head :bad_request
  rescue JSON::ParserError
    head :bad_request
  end
end

