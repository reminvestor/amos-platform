# app/services/ses_event_service.rb
class SesEventService
  def process_event(notification)
    # The notification might be raw JSON or parsed hash depending on how it comes in
    message = notification["Message"]
    return unless message

    # AWS SNS messages are JSON encoded strings
    event = JSON.parse(message) rescue nil
    return unless event

    event_type = event["eventType"]
    mail = event["mail"]
    
    return unless mail && mail["messageId"]

    # SES message ID
    message_id = mail["messageId"]

    # Find the delivery
    delivery = EmailDelivery.find_by(ses_message_id: message_id)
    return unless delivery

    case event_type
    when "Delivery"
      handle_delivery(delivery, event["delivery"])
    when "Open"
      handle_open(delivery, event["open"])
    when "Click"
      handle_click(delivery, event["click"])
    when "Bounce"
      handle_bounce(delivery, event["bounce"])
    when "Complaint"
      handle_complaint(delivery, event["complaint"])
    end
  end

  private

  def handle_delivery(delivery, data)
    delivery.update(
      status: "delivered",
      sent_at: data["timestamp"] ? Time.parse(data["timestamp"]) : Time.current
    )
  end

  def handle_open(delivery, data)
    # Only update if not already opened or if this is newer
    timestamp = data["timestamp"] ? Time.parse(data["timestamp"]) : Time.current
    
    if delivery.opened_at.nil? || timestamp > delivery.opened_at
      delivery.update(
        status: "opened",
        opened_at: timestamp
      )
    end
  end

  def handle_click(delivery, data)
    timestamp = data["timestamp"] ? Time.parse(data["timestamp"]) : Time.current
    
    # Click implies open
    if delivery.opened_at.nil?
      delivery.update(opened_at: timestamp)
    end

    if delivery.clicked_at.nil? || timestamp > delivery.clicked_at
      delivery.update(
        status: "clicked",
        clicked_at: timestamp
      )
    end
  end

  def handle_bounce(delivery, data)
    bounce_type = data["bounceType"]
    bounce_sub_type = data["bounceSubType"]
    reason = "Bounce: #{bounce_type}/#{bounce_sub_type}"
    
    delivery.mark_as_bounced(reason)
  end

  def handle_complaint(delivery, data)
    complaint_type = data["complaintFeedbackType"]
    
    # Mark contact as opted out
    delivery.contact.update(
      opted_out: true,
      opted_out_at: Time.current
    )
    
    delivery.update(
      status: "failed", 
      error_message: "Complaint: #{complaint_type}"
    )
  end
end

