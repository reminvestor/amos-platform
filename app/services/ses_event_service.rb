# app/services/ses_event_service.rb
#
# Processes SES email events received via SNS webhooks.
# Handles both campaign emails (EmailDelivery) and sequence emails (SequenceEmailDelivery).
#
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
    
    # Parse message tags to determine email type
    tags = parse_message_tags(mail["tags"] || mail["headers"])
    email_type = tags["type"] || "campaign"

    # Find the appropriate delivery record
    if email_type == "sequence"
      process_sequence_event(message_id, event_type, event, tags)
    else
      process_campaign_event(message_id, event_type, event)
    end
  end

  private

  # Parse SES message tags from various formats
  def parse_message_tags(tags_data)
    return {} unless tags_data
    
    tags = {}
    
    if tags_data.is_a?(Hash)
      # Direct hash format
      tags_data.each { |k, v| tags[k.to_s] = v.to_s }
    elsif tags_data.is_a?(Array)
      # Array of {name, value} pairs
      tags_data.each do |tag|
        if tag.is_a?(Hash)
          name = tag["name"] || tag["Name"]
          value = tag["value"] || tag["Value"]
          tags[name.to_s] = value.to_s if name
        end
      end
    end
    
    tags
  end

  # ============================================
  # Campaign Email Processing (existing)
  # ============================================
  
  def process_campaign_event(message_id, event_type, event)
    delivery = EmailDelivery.find_by(ses_message_id: message_id)
    return unless delivery

    case event_type
    when "Delivery"
      handle_campaign_delivery(delivery, event["delivery"])
    when "Open"
      handle_campaign_open(delivery, event["open"])
    when "Click"
      handle_campaign_click(delivery, event["click"])
    when "Bounce"
      handle_campaign_bounce(delivery, event["bounce"])
    when "Complaint"
      handle_campaign_complaint(delivery, event["complaint"])
    end
  end

  def handle_campaign_delivery(delivery, data)
    delivery.update(
      status: "delivered",
      sent_at: data["timestamp"] ? Time.parse(data["timestamp"]) : Time.current
    )
  end

  def handle_campaign_open(delivery, data)
    timestamp = data["timestamp"] ? Time.parse(data["timestamp"]) : Time.current
    
    if delivery.opened_at.nil? || timestamp > delivery.opened_at
      delivery.update(
        status: "opened",
        opened_at: timestamp
      )
    end
  end

  def handle_campaign_click(delivery, data)
    timestamp = data["timestamp"] ? Time.parse(data["timestamp"]) : Time.current
    
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

  def handle_campaign_bounce(delivery, data)
    bounce_type = data["bounceType"]
    bounce_sub_type = data["bounceSubType"]
    reason = "Bounce: #{bounce_type}/#{bounce_sub_type}"
    
    delivery.mark_as_bounced(reason)
  end

  def handle_campaign_complaint(delivery, data)
    complaint_type = data["complaintFeedbackType"]
    
    delivery.contact.update(
      opted_out: true,
      opted_out_at: Time.current
    )
    
    delivery.update(
      status: "failed", 
      error_message: "Complaint: #{complaint_type}"
    )
  end

  # ============================================
  # Sequence Email Processing (new)
  # ============================================
  
  def process_sequence_event(message_id, event_type, event, tags)
    # Try to find by message ID first
    delivery = SequenceEmailDelivery.find_by(ses_message_id: message_id)
    
    # Fallback: find by delivery_id tag if message_id lookup fails
    unless delivery
      delivery_id = tags["delivery_id"]
      delivery = SequenceEmailDelivery.find_by(id: delivery_id) if delivery_id
    end
    
    return unless delivery
    
    Rails.logger.info "[SesEventService] Processing #{event_type} for sequence delivery #{delivery.id}"

    case event_type
    when "Delivery"
      handle_sequence_delivery(delivery, event["delivery"])
    when "Open"
      handle_sequence_open(delivery, event["open"])
    when "Click"
      handle_sequence_click(delivery, event["click"])
    when "Bounce"
      handle_sequence_bounce(delivery, event["bounce"])
    when "Complaint"
      handle_sequence_complaint(delivery, event["complaint"])
    end
  end

  def handle_sequence_delivery(delivery, data)
    delivery.mark_as_delivered
    Rails.logger.info "[SesEventService] Sequence email delivered: #{delivery.id}"
  end

  def handle_sequence_open(delivery, data)
    delivery.mark_as_opened
    
    # Create activity
    Activity.create(
      entity: delivery.entity,
      contact: delivery.contact,
      activity_type: 'email_opened',
      subject: "Opened: #{delivery.sequence_step.effective_subject}",
      description: "Opened email from sequence '#{delivery.email_sequence.name}' (step #{delivery.sequence_step.step_number})",
      status: 'completed',
      completed_at: Time.current,
      metadata: {
        sequence_id: delivery.email_sequence_id,
        step_number: delivery.sequence_step.step_number,
        delivery_id: delivery.id
      }
    )
    
    Rails.logger.info "[SesEventService] Sequence email opened: #{delivery.id}"
  rescue => e
    Rails.logger.warn "[SesEventService] Failed to record open activity: #{e.message}"
  end

  def handle_sequence_click(delivery, data)
    delivery.mark_as_clicked
    
    clicked_url = data&.dig("link")
    
    # Create activity
    Activity.create(
      entity: delivery.entity,
      contact: delivery.contact,
      activity_type: 'email_clicked',
      subject: "Clicked: #{delivery.sequence_step.effective_subject}",
      description: "Clicked link in sequence '#{delivery.email_sequence.name}' (step #{delivery.sequence_step.step_number})",
      status: 'completed',
      completed_at: Time.current,
      metadata: {
        sequence_id: delivery.email_sequence_id,
        step_number: delivery.sequence_step.step_number,
        delivery_id: delivery.id,
        clicked_url: clicked_url
      }
    )
    
    Rails.logger.info "[SesEventService] Sequence email clicked: #{delivery.id}"
  rescue => e
    Rails.logger.warn "[SesEventService] Failed to record click activity: #{e.message}"
  end

  def handle_sequence_bounce(delivery, data)
    bounce_type = data["bounceType"]
    bounce_sub_type = data["bounceSubType"]
    reason = "Bounce: #{bounce_type}/#{bounce_sub_type}"
    
    delivery.mark_as_bounced(reason)
    
    # Create activity
    Activity.create(
      entity: delivery.entity,
      contact: delivery.contact,
      activity_type: 'email_bounced',
      subject: "Email bounced (#{bounce_type})",
      description: "Email to #{delivery.contact.email} bounced: #{reason}",
      status: 'completed',
      completed_at: Time.current,
      metadata: {
        sequence_id: delivery.email_sequence_id,
        step_number: delivery.sequence_step.step_number,
        bounce_type: bounce_type,
        bounce_sub_type: bounce_sub_type
      }
    )
    
    Rails.logger.info "[SesEventService] Sequence email bounced: #{delivery.id} - #{reason}"
  rescue => e
    Rails.logger.warn "[SesEventService] Failed to record bounce activity: #{e.message}"
  end

  def handle_sequence_complaint(delivery, data)
    complaint_type = data["complaintFeedbackType"]
    
    delivery.mark_as_complaint
    
    Activity.create(
      entity: delivery.entity,
      contact: delivery.contact,
      activity_type: 'spam_complaint',
      subject: "Marked as spam",
      description: "Contact marked sequence email as spam",
      status: 'completed',
      completed_at: Time.current,
      metadata: {
        sequence_id: delivery.email_sequence_id,
        complaint_type: complaint_type
      }
    )
    
    Rails.logger.info "[SesEventService] Sequence email complaint: #{delivery.id}"
  rescue => e
    Rails.logger.warn "[SesEventService] Failed to record complaint activity: #{e.message}"
  end
end

