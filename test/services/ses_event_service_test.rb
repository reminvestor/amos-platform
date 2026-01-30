require 'test_helper'

class SesEventServiceTest < ActiveSupport::TestCase
  setup do
    @service = SesEventService.new
    @entity = entities(:default)
    @contact = contacts(:one)
    @contact.update!(opted_out: false)
  end

  # ============================================
  # Campaign Email Tests (Existing Behavior)
  # ============================================

  test "processes campaign delivery event" do
    delivery = email_deliveries(:sent_delivery)
    delivery.update!(ses_message_id: "campaign-delivery-123", status: "sent")
    
    event = build_ses_event("Delivery", "campaign-delivery-123", {
      "delivery" => { "timestamp" => Time.current.iso8601 }
    })
    
    @service.process_event(event)
    
    delivery.reload
    assert_equal "delivered", delivery.status
  end

  test "processes campaign open event" do
    delivery = email_deliveries(:sent_delivery)
    delivery.update!(ses_message_id: "campaign-open-123", status: "delivered")
    
    event = build_ses_event("Open", "campaign-open-123", {
      "open" => { "timestamp" => Time.current.iso8601 }
    })
    
    @service.process_event(event)
    
    delivery.reload
    assert_equal "opened", delivery.status
    assert_not_nil delivery.opened_at
  end

  test "processes campaign click event" do
    delivery = email_deliveries(:sent_delivery)
    delivery.update!(ses_message_id: "campaign-click-123", status: "delivered")
    
    event = build_ses_event("Click", "campaign-click-123", {
      "click" => { "timestamp" => Time.current.iso8601, "link" => "https://example.com" }
    })
    
    @service.process_event(event)
    
    delivery.reload
    assert_equal "clicked", delivery.status
    assert_not_nil delivery.clicked_at
    assert_not_nil delivery.opened_at # Click implies open
  end

  test "processes campaign bounce event" do
    delivery = email_deliveries(:sent_delivery)
    delivery.update!(ses_message_id: "campaign-bounce-123", status: "sent")
    
    event = build_ses_event("Bounce", "campaign-bounce-123", {
      "bounce" => { "bounceType" => "Permanent", "bounceSubType" => "General" }
    })
    
    @service.process_event(event)
    
    delivery.reload
    assert_equal "bounced", delivery.status
  end

  # ============================================
  # Sequence Email Tests (New Behavior)
  # ============================================

  test "processes sequence delivery event" do
    delivery = create_sequence_delivery("seq-delivery-123")
    
    event = build_ses_event("Delivery", "seq-delivery-123", {
      "delivery" => { "timestamp" => Time.current.iso8601 }
    }, type: "sequence", delivery_id: delivery.id)
    
    @service.process_event(event)
    
    delivery.reload
    assert_equal "delivered", delivery.status
    assert_not_nil delivery.delivered_at
  end

  test "processes sequence open event and increments step metrics" do
    delivery = create_sequence_delivery("seq-open-123", status: "delivered")
    initial_opened = delivery.sequence_step.opened_count
    
    event = build_ses_event("Open", "seq-open-123", {
      "open" => { "timestamp" => Time.current.iso8601 }
    }, type: "sequence", delivery_id: delivery.id)
    
    @service.process_event(event)
    
    delivery.reload
    assert_equal "opened", delivery.status
    assert_not_nil delivery.opened_at
    
    delivery.sequence_step.reload
    assert_equal initial_opened + 1, delivery.sequence_step.opened_count
  end

  test "processes sequence open event and creates activity" do
    delivery = create_sequence_delivery("seq-open-activity-123", status: "delivered")
    
    event = build_ses_event("Open", "seq-open-activity-123", {
      "open" => { "timestamp" => Time.current.iso8601 }
    }, type: "sequence", delivery_id: delivery.id)
    
    assert_difference 'Activity.count', 1 do
      @service.process_event(event)
    end
    
    activity = Activity.last
    assert_equal 'email_opened', activity.activity_type
    assert_equal @contact, activity.contact
  end

  test "processes sequence click event and increments step metrics" do
    delivery = create_sequence_delivery("seq-click-123", status: "delivered")
    initial_clicked = delivery.sequence_step.clicked_count
    
    event = build_ses_event("Click", "seq-click-123", {
      "click" => { "timestamp" => Time.current.iso8601, "link" => "https://example.com" }
    }, type: "sequence", delivery_id: delivery.id)
    
    @service.process_event(event)
    
    delivery.reload
    assert_equal "clicked", delivery.status
    assert_not_nil delivery.clicked_at
    
    delivery.sequence_step.reload
    assert_equal initial_clicked + 1, delivery.sequence_step.clicked_count
  end

  test "processes sequence click event and creates activity" do
    delivery = create_sequence_delivery("seq-click-activity-123", status: "delivered")
    
    event = build_ses_event("Click", "seq-click-activity-123", {
      "click" => { "timestamp" => Time.current.iso8601, "link" => "https://example.com" }
    }, type: "sequence", delivery_id: delivery.id)
    
    assert_difference 'Activity.count', 1 do
      @service.process_event(event)
    end
    
    activity = Activity.last
    assert_equal 'email_clicked', activity.activity_type
    assert_includes activity.metadata['clicked_url'], "https://example.com"
  end

  test "processes sequence bounce event cancels enrollment" do
    delivery = create_sequence_delivery("seq-bounce-123", status: "sent")
    enrollment = delivery.sequence_enrollment
    enrollment.update!(status: 'active')
    
    event = build_ses_event("Bounce", "seq-bounce-123", {
      "bounce" => { "bounceType" => "Permanent", "bounceSubType" => "General" }
    }, type: "sequence", delivery_id: delivery.id)
    
    @service.process_event(event)
    
    delivery.reload
    enrollment.reload
    
    assert_equal "bounced", delivery.status
    assert_equal "cancelled", enrollment.status
  end

  test "processes sequence bounce event opts out contact" do
    delivery = create_sequence_delivery("seq-bounce-optout-123", status: "sent")
    @contact.update!(opted_out: false)
    
    event = build_ses_event("Bounce", "seq-bounce-optout-123", {
      "bounce" => { "bounceType" => "Permanent", "bounceSubType" => "General" }
    }, type: "sequence", delivery_id: delivery.id)
    
    @service.process_event(event)
    
    @contact.reload
    assert @contact.opted_out?
  end

  test "processes sequence bounce event creates activity" do
    delivery = create_sequence_delivery("seq-bounce-activity-123", status: "sent")
    
    event = build_ses_event("Bounce", "seq-bounce-activity-123", {
      "bounce" => { "bounceType" => "Permanent", "bounceSubType" => "General" }
    }, type: "sequence", delivery_id: delivery.id)
    
    assert_difference 'Activity.count', 1 do
      @service.process_event(event)
    end
    
    activity = Activity.last
    assert_equal 'email_bounced', activity.activity_type
  end

  test "processes sequence complaint event opts out contact" do
    delivery = create_sequence_delivery("seq-complaint-123", status: "delivered")
    @contact.update!(opted_out: false)
    
    event = build_ses_event("Complaint", "seq-complaint-123", {
      "complaint" => { "complaintFeedbackType" => "abuse" }
    }, type: "sequence", delivery_id: delivery.id)
    
    @service.process_event(event)
    
    delivery.reload
    @contact.reload
    
    assert_equal "failed", delivery.status
    assert @contact.opted_out?
  end

  test "processes sequence complaint event cancels enrollment" do
    delivery = create_sequence_delivery("seq-complaint-cancel-123", status: "delivered")
    enrollment = delivery.sequence_enrollment
    enrollment.update!(status: 'active')
    
    event = build_ses_event("Complaint", "seq-complaint-cancel-123", {
      "complaint" => { "complaintFeedbackType" => "abuse" }
    }, type: "sequence", delivery_id: delivery.id)
    
    @service.process_event(event)
    
    enrollment.reload
    assert_equal "cancelled", enrollment.status
  end

  # ============================================
  # Edge Cases
  # ============================================

  test "ignores event with missing message" do
    event = { "NotMessage" => "something" }
    
    # Should not raise
    assert_nothing_raised do
      @service.process_event(event)
    end
  end

  test "ignores event with invalid JSON message" do
    event = { "Message" => "not valid json {{{" }
    
    assert_nothing_raised do
      @service.process_event(event)
    end
  end

  test "ignores event with unknown message ID" do
    event = build_ses_event("Delivery", "unknown-message-id-123", {
      "delivery" => { "timestamp" => Time.current.iso8601 }
    })
    
    assert_nothing_raised do
      @service.process_event(event)
    end
  end

  test "finds sequence delivery by delivery_id tag when message_id lookup fails" do
    delivery = create_sequence_delivery(nil, status: "sent") # No message ID
    
    event = build_ses_event("Delivery", "different-message-id", {
      "delivery" => { "timestamp" => Time.current.iso8601 }
    }, type: "sequence", delivery_id: delivery.id)
    
    @service.process_event(event)
    
    delivery.reload
    assert_equal "delivered", delivery.status
  end

  test "parses message tags from hash format" do
    delivery = create_sequence_delivery("hash-tags-123", status: "sent")
    
    # Tags as direct hash (some SES versions)
    event = {
      "Message" => {
        "eventType" => "Delivery",
        "mail" => {
          "messageId" => "hash-tags-123",
          "tags" => { "type" => "sequence", "delivery_id" => delivery.id.to_s }
        },
        "delivery" => { "timestamp" => Time.current.iso8601 }
      }.to_json
    }
    
    @service.process_event(event)
    
    delivery.reload
    assert_equal "delivered", delivery.status
  end

  private

  def build_ses_event(event_type, message_id, event_data, type: nil, delivery_id: nil)
    tags = []
    tags << { "name" => "type", "value" => type } if type
    tags << { "name" => "delivery_id", "value" => delivery_id.to_s } if delivery_id
    
    {
      "Message" => {
        "eventType" => event_type,
        "mail" => {
          "messageId" => message_id,
          "tags" => tags
        }
      }.merge(event_data).to_json
    }
  end

  def create_sequence_delivery(message_id, status: "pending")
    sequence = email_sequences(:active_sequence)
    step = sequence.sequence_steps.first || sequence.sequence_steps.create!(
      step_number: 1, delay_hours: 0, subject: "Test", body: "Test body"
    )
    enrollment = sequence.sequence_enrollments.find_by(contact: @contact) ||
                 sequence.sequence_enrollments.create!(contact: @contact, entity: @entity, status: 'active')
    
    SequenceEmailDelivery.create!(
      email_sequence: sequence,
      sequence_step: step,
      sequence_enrollment: enrollment,
      contact: @contact,
      entity: @entity,
      status: status,
      ses_message_id: message_id
    )
  end
end
