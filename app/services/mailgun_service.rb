class MailgunService
  attr_reader :api_key, :domain
  
  def initialize(api_key = nil, domain = nil)
    @api_key = api_key || ENV['MAILGUN_API_KEY']
    @domain = domain || ENV['MAILGUN_DOMAIN']
    
    raise "Mailgun API key is missing" if @api_key.blank?
    raise "Mailgun domain is missing" if @domain.blank?
  end
  
  # Fetch events for a specific message
  def get_events(message_id)
    response = mailgun_request(
      "#{domain}/events",
      { message_id: message_id }
    )
    
    response["items"] || []
  end
  
  # Fetch stats for a campaign
  def get_campaign_stats(campaign_tag)
    response = mailgun_request(
      "#{domain}/stats/total",
      { 
        event: ['delivered', 'opened', 'clicked', 'unsubscribed', 'complained', 'failed'],
        tags: campaign_tag,
        duration: '30d' # Last 30 days
      }
    )
    
    response["stats"] || []
  end
  
  # Fetch delivery status for a batch of messages
  def get_messages_status(message_ids)
    results = {}
    message_ids.each_slice(100) do |batch|
      batch.each do |msg_id|
        response = mailgun_request("#{domain}/messages/#{msg_id}")
        results[msg_id] = response if response
      end
    end
    results
  end
  
  # Fetch all events for a campaign tag
  def get_campaign_events(campaign_tag, event_types = nil)
    params = { tags: campaign_tag }
    params[:event] = event_types if event_types
    
    response = mailgun_request("#{domain}/events", params)
    response["items"] || []
  end
  
  # Sync delivery data for a campaign
  def sync_campaign_stats(campaign)
    # Skip if campaign doesn't have a tag
    return unless campaign.mailgun_tag.present?
    
    # Get stats from Mailgun
    stats = get_campaign_stats(campaign.mailgun_tag)
    return if stats.empty?
    
    # Get all message events
    events = get_campaign_events(campaign.mailgun_tag)
    
    # Process each delivery and update stats
    campaign.email_deliveries.each do |delivery|
      next unless delivery.mailgun_message_id.present?
      
      # Find events for this specific message
      message_events = events.select { |e| e["message"]["headers"]["message-id"] == delivery.mailgun_message_id }
      
      # Update delivery status based on events
      update_delivery_status(delivery, message_events)
    end
    
    # Update campaign aggregated stats
    update_campaign_stats(campaign, stats.first)
    
    true
  end
  
  private
  
  def mailgun_request(endpoint, params = {})
    begin
      url = "https://api.mailgun.net/v3/#{endpoint}"
      
      response = HTTParty.get(
        url,
        basic_auth: { username: 'api', password: api_key },
        query: params,
        headers: { 'Accept' => 'application/json' }
      )
      
      if response.success?
        JSON.parse(response.body)
      else
        Rails.logger.error("Mailgun API error: #{response.code} #{response.message} - #{response.body}")
        nil
      end
    rescue => e
      Rails.logger.error("Mailgun API request failed: #{e.message}")
      nil
    end
  end
  
  def update_delivery_status(delivery, events)
    # Find the most recent status events
    delivered = events.find { |e| e["event"] == "delivered" }
    opened = events.find { |e| e["event"] == "opened" }
    clicked = events.find { |e| e["event"] == "clicked" }
    failed = events.find { |e| e["event"] == "failed" }
    complained = events.find { |e| e["event"] == "complained" }
    unsubscribed = events.find { |e| e["event"] == "unsubscribed" }
    
    # Update the delivery status and timestamps
    if delivered
      delivery.update(
        status: 'delivered',
        sent_at: Time.at(delivered["timestamp"]).utc,
        mailgun_status: 'delivered'
      )
    end
    
    if opened && (delivery.opened_at.nil? || Time.at(opened["timestamp"]).utc > delivery.opened_at)
      delivery.update(
        status: 'opened',
        opened_at: Time.at(opened["timestamp"]).utc
      )
    end
    
    if clicked && (delivery.clicked_at.nil? || Time.at(clicked["timestamp"]).utc > delivery.clicked_at)
      delivery.update(
        status: 'clicked',
        clicked_at: Time.at(clicked["timestamp"]).utc
      )
    end
    
    if failed
      delivery.update(
        status: 'failed',
        error_message: failed["reason"] || failed["severity"] || "Delivery failed",
        mailgun_status: 'failed'
      )
    end
    
    if unsubscribed
      # Update the contact's opt-out status
      delivery.contact.update(
        opted_out: true,
        opted_out_at: Time.at(unsubscribed["timestamp"]).utc
      )
    end
  end
  
  def update_campaign_stats(campaign, stats)
    # Only update if we have stats data
    return unless stats
    
    # Calculate totals from raw stats
    delivered = stats["delivered"] || { "total" => 0 }
    opened = stats["opened"] || { "total" => 0 }
    clicked = stats["clicked"] || { "total" => 0 }
    complained = stats["complained"] || { "total" => 0 }
    failed = stats["failed"] || { "total" => 0 }
    
    # Store the stats in the campaign
    campaign.update(
      mailgun_stats: {
        delivered: delivered["total"],
        opened: opened["total"],
        clicked: clicked["total"],
        complained: complained["total"],
        failed: failed["total"],
        last_synced_at: Time.current
      }
    )
  end
end 