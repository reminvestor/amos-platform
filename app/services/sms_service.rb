class SmsService
  def initialize(entity)
    @entity = entity
    @connection = find_twilio_connection
  end

  # Send a single SMS
  def send_message(to:, body:, campaign: nil, contact: nil)
    require 'twilio-ruby'
    validate_connection!

    client = Twilio::REST::Client.new(account_sid, auth_token)

    message = client.messages.create(
      from: from_number,
      to: format_phone_number(to),
      body: body
    )

    # Record delivery
    if campaign && contact
      SmsDelivery.create!(
        sms_campaign: campaign,
        contact: contact,
        to_number: to,
        twilio_sid: message.sid,
        status: 'sent',
        metadata: { sent_at: Time.current }
      )
    end

    { success: true, sid: message.sid, status: message.status }
  rescue => e
    require 'twilio-ruby'
    if e.is_a?(Twilio::REST::RestError)
      Rails.logger.error "[SmsService] Twilio error: #{e.message}"
    else
      Rails.logger.error "[SmsService] Error: #{e.message}"
    end

    if campaign && contact
      SmsDelivery.create!(
        sms_campaign: campaign,
        contact: contact,
        to_number: to,
        status: 'failed',
        error_message: e.message
      )
    end

    { success: false, error: e.message }
  end

  # Handle Twilio delivery status webhooks
  def handle_webhook(params)
    delivery = SmsDelivery.find_by(twilio_sid: params['MessageSid'])
    return unless delivery

    status_map = {
      'queued' => 'queued',
      'sending' => 'sent',
      'sent' => 'sent',
      'delivered' => 'delivered',
      'undelivered' => 'undelivered',
      'failed' => 'failed'
    }

    new_status = status_map[params['MessageStatus']] || 'failed'

    delivery.update!(
      status: new_status,
      delivered_at: (Time.current if new_status == 'delivered'),
      error_message: params['ErrorMessage'],
      metadata: delivery.metadata.merge(
        status_updated_at: Time.current,
        twilio_status: params['MessageStatus']
      )
    )

    # Update campaign counters
    update_campaign_counters(delivery.sms_campaign)
  end

  # Get SMS analytics for a campaign
  def get_campaign_analytics(campaign)
    deliveries = campaign.sms_deliveries

    {
      total_sent: deliveries.count,
      delivered: deliveries.delivered.count,
      failed: deliveries.failed.count,
      pending: deliveries.pending.count,
      delivery_rate: campaign.delivery_rate,
      failure_rate: campaign.failure_rate,
      cost_estimate: calculate_cost(deliveries.count)
    }
  end

  private

  def find_twilio_connection
    integration = Integration.find_by(slug: 'twilio')
    return nil unless integration

    Connection.find_by(entity: @entity, integration: integration)
  end

  def validate_connection!
    raise "Twilio connection not configured" unless @connection
    raise "Missing Twilio credentials" unless account_sid && auth_token && from_number
  end

  def account_sid
    @connection.credentials&.dig('account_sid')
  end

  def auth_token
    @connection.credentials&.dig('auth_token')
  end

  def from_number
    @connection.credentials&.dig('from_number')
  end

  def format_phone_number(number)
    # Ensure E.164 format (+1XXXXXXXXXX for US)
    number = number.to_s.gsub(/\D/, '') # Remove non-digits

    # Add country code if missing (assume US +1)
    number = "1#{number}" unless number.start_with?('1')

    "+#{number}"
  end

  def calculate_cost(message_count)
    # Twilio pricing: approximately $0.0075 per SMS in US
    (message_count * 0.0075).round(2)
  end

  def update_campaign_counters(campaign)
    campaign.update!(
      delivered_count: campaign.sms_deliveries.delivered.count,
      failed_count: campaign.sms_deliveries.failed.count
    )
  end
end
