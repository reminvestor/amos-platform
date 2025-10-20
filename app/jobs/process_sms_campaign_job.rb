class ProcessSmsCampaignJob < ApplicationJob
  queue_as :default

  def perform(sms_campaign_id)
    campaign = SmsCampaign.find(sms_campaign_id)
    campaign.update!(status: 'sending')

    sms_service = SmsService.new(campaign.entity)

    # Get recipients (contacts with phone numbers)
    recipients = campaign.entity.contacts.where.not(phone: nil)
    campaign.update!(total_recipients: recipients.count)

    Rails.logger.info "[ProcessSmsCampaignJob] Sending #{recipients.count} SMS messages for campaign #{campaign.id}"

    recipients.find_each do |contact|
      begin
        # Personalize message
        message = personalize_message(campaign.message_body, contact)

        # Validate message length
        if message.length > 1600
          Rails.logger.warn "[ProcessSmsCampaignJob] Message too long for contact #{contact.id}, truncating"
          message = message[0..1596] + "..."
        end

        # Send SMS
        result = sms_service.send_message(
          to: contact.phone,
          body: message,
          campaign: campaign,
          contact: contact
        )

        if result[:success]
          Rails.logger.debug "[ProcessSmsCampaignJob] Sent to #{contact.phone}"
          campaign.increment!(:delivered_count)
        else
          Rails.logger.error "[ProcessSmsCampaignJob] Failed to send to #{contact.phone}: #{result[:error]}"
          campaign.increment!(:failed_count)
        end

        # Rate limiting (Twilio allows ~1/sec on trial, higher on paid)
        sleep 1
      rescue => e
        Rails.logger.error "[ProcessSmsCampaignJob] Error sending to contact #{contact.id}: #{e.message}"
        campaign.increment!(:failed_count)
      end
    end

    campaign.update!(status: 'sent')
    Rails.logger.info "[ProcessSmsCampaignJob] Completed campaign #{campaign.id}: #{campaign.delivered_count}/#{campaign.total_recipients} delivered"
  rescue => e
    Rails.logger.error "[ProcessSmsCampaignJob] Campaign #{sms_campaign_id} failed: #{e.message}"
    campaign&.update!(status: 'failed')
    raise
  end

  private

  def personalize_message(template, contact)
    message = template.dup

    # Replace common placeholders
    replacements = {
      '{{first_name}}' => contact.first_name || 'there',
      '{{last_name}}' => contact.last_name || '',
      '{{full_name}}' => contact.full_name || 'there',
      '{{email}}' => contact.email || '',
      '{{company}}' => contact.company || ''
    }

    replacements.each do |placeholder, value|
      message.gsub!(placeholder, value.to_s)
    end

    message
  end
end
