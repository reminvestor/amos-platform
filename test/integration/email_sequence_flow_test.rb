# frozen_string_literal: true

require 'test_helper'

class EmailSequenceFlowTest < ActionDispatch::IntegrationTest
  setup do
    @entity = entities(:default)
    @user = users(:one)
    @contact_group = contact_groups(:default_group)
    
    # Ensure we have contacts in the group
    @contacts = [contacts(:one), contacts(:two)]
    @contacts.each do |contact|
      contact.contact_groups << @contact_group unless contact.contact_groups.include?(@contact_group)
    end
    
    # Sign in
    sign_in @user
  end

  # ============================================
  # End-to-End Flow Test
  # ============================================
  
  test "complete email sequence flow from creation to delivery" do
    # Step 1: Create a new email sequence
    sequence = EmailSequence.create!(
      name: "Integration Test Sequence",
      goal: "Test the complete email sequence flow",
      status: "draft",
      entity: @entity,
      contact_group: @contact_group
    )
    
    assert_equal "draft", sequence.status
    assert_equal 0, sequence.step_count
    
    # Step 2: Add sequence steps
    step1 = sequence.sequence_steps.create!(
      step_number: 1,
      delay_hours: 0,
      subject: "Welcome to our test!",
      body: "<p>Hello {{first_name}}, welcome!</p>"
    )
    
    step2 = sequence.sequence_steps.create!(
      step_number: 2,
      delay_hours: 24,
      subject: "Getting Started",
      body: "<p>Hi {{first_name}}, here's how to get started.</p>"
    )
    
    step3 = sequence.sequence_steps.create!(
      step_number: 3,
      delay_hours: 72,
      subject: "Pro Tips",
      body: "<p>Hi {{first_name}}, some pro tips for you.</p>"
    )
    
    sequence.reload
    assert_equal 3, sequence.step_count
    
    # Step 3: Enroll contacts
    enrolled = sequence.enroll_contacts!
    assert_equal @contacts.count, enrolled
    assert_equal @contacts.count, sequence.sequence_enrollments.count
    
    # All enrollments should be pending
    assert sequence.sequence_enrollments.all? { |e| e.status == 'pending' }
    
    # Step 4: Activate the sequence
    assert sequence.activate!
    sequence.reload
    assert_equal "active", sequence.status
    
    # Step 5: Process enrollments (simulating the job)
    ProcessSequenceEnrollmentsJob.perform_now(sequence.id)
    
    sequence.reload
    assert_equal @contacts.count, sequence.active_count
    
    # Enrollments should now be active with next_send_at set
    sequence.sequence_enrollments.reload.each do |enrollment|
      assert_equal "active", enrollment.status
      assert_not_nil enrollment.started_at
      assert_not_nil enrollment.next_send_at
      assert_equal step1.step_number, enrollment.current_step_number
    end
    
    # Step 6: Send emails for ready enrollments
    assert_emails @contacts.count do
      SendSequenceEmailsJob.perform_now(sequence.id)
    end
    
    # Verify step1 was sent
    step1.reload
    assert_equal @contacts.count, step1.sent_count
    
    # Verify delivery records were created
    deliveries = SequenceEmailDelivery.where(email_sequence: sequence, sequence_step: step1)
    assert_equal @contacts.count, deliveries.count
    deliveries.each do |delivery|
      assert_equal "sent", delivery.status
      assert_not_nil delivery.sent_at
    end
    
    # Enrollments should have advanced to step 2
    sequence.sequence_enrollments.reload.each do |enrollment|
      assert_equal step2.step_number, enrollment.current_step_number
      # next_send_at should be 24 hours from now
      assert enrollment.next_send_at > Time.current
    end
    
    # Step 7: Simulate time passing and send step 2
    travel 25.hours do
      assert_emails @contacts.count do
        SendSequenceEmailsJob.perform_now(sequence.id)
      end
      
      step2.reload
      assert_equal @contacts.count, step2.sent_count
    end
    
    # Step 8: Simulate time passing and send step 3 (final step)
    travel 4.days do
      assert_emails @contacts.count do
        SendSequenceEmailsJob.perform_now(sequence.id)
      end
      
      step3.reload
      assert_equal @contacts.count, step3.sent_count
      
      # All enrollments should be completed
      sequence.sequence_enrollments.reload.each do |enrollment|
        assert_equal "completed", enrollment.status
        assert_not_nil enrollment.completed_at
      end
    end
    
    # Verify final stats
    sequence.reload
    assert_equal @contacts.count, sequence.completed_count
    assert_equal 0, sequence.active_count
    assert_equal 100.0, sequence.completion_rate
  end

  # ============================================
  # API Tests
  # ============================================
  
  test "API: list email sequences" do
    get api_v1_email_sequences_path, headers: api_headers
    
    assert_response :success
    json = JSON.parse(response.body)
    assert json['success']
    assert_kind_of Array, json['sequences']
  end

  test "API: create email sequence" do
    assert_difference 'EmailSequence.count', 1 do
      post api_v1_email_sequences_path, 
        params: { 
          email_sequence: { 
            name: "API Test Sequence",
            goal: "Test via API",
            contact_group_id: @contact_group.id
          } 
        },
        headers: api_headers
    end
    
    assert_response :created
    json = JSON.parse(response.body)
    assert json['success']
    assert_equal "API Test Sequence", json['sequence']['name']
  end

  test "API: activate sequence" do
    sequence = email_sequences(:welcome_sequence)
    # Ensure it has steps
    sequence.sequence_steps.create!(step_number: 99, delay_hours: 0, subject: "Test", body: "Test")
    
    post activate_api_v1_email_sequence_path(sequence), headers: api_headers
    
    assert_response :success
    json = JSON.parse(response.body)
    assert json['success']
    assert_equal "active", json['sequence']['status']
  end

  test "API: pause and resume sequence" do
    sequence = email_sequences(:active_sequence)
    
    # Pause
    post pause_api_v1_email_sequence_path(sequence), headers: api_headers
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "paused", json['sequence']['status']
    
    # Resume
    post resume_api_v1_email_sequence_path(sequence), headers: api_headers
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "active", json['sequence']['status']
  end

  test "API: get sequence stats" do
    sequence = email_sequences(:active_sequence)
    
    get stats_api_v1_email_sequence_path(sequence), headers: api_headers
    
    assert_response :success
    json = JSON.parse(response.body)
    assert json['success']
    assert_kind_of Hash, json['stats']
    assert_equal sequence.name, json['stats']['name']
  end

  # ============================================
  # SES Event Processing Tests
  # ============================================
  
  test "SES event: delivery updates sequence email delivery" do
    # Create a delivery record
    sequence = email_sequences(:active_sequence)
    step = sequence.sequence_steps.first || sequence.sequence_steps.create!(step_number: 1, delay_hours: 0, subject: "Test", body: "Test")
    contact = contacts(:one)
    enrollment = sequence.sequence_enrollments.create!(contact: contact, entity: @entity, status: 'active')
    
    delivery = SequenceEmailDelivery.create!(
      email_sequence: sequence,
      sequence_step: step,
      sequence_enrollment: enrollment,
      contact: contact,
      entity: @entity,
      status: 'sent',
      ses_message_id: 'test-message-id-123'
    )
    
    # Simulate SES delivery event
    ses_event = {
      "Message" => {
        "eventType" => "Delivery",
        "mail" => {
          "messageId" => "test-message-id-123",
          "tags" => [
            { "name" => "type", "value" => "sequence" },
            { "name" => "delivery_id", "value" => delivery.id.to_s }
          ]
        },
        "delivery" => {
          "timestamp" => Time.current.iso8601
        }
      }.to_json
    }
    
    SesEventService.new.process_event(ses_event)
    
    delivery.reload
    assert_equal "delivered", delivery.status
  end

  test "SES event: open updates sequence email delivery and step metrics" do
    sequence = email_sequences(:active_sequence)
    step = sequence.sequence_steps.first || sequence.sequence_steps.create!(step_number: 1, delay_hours: 0, subject: "Test", body: "Test")
    contact = contacts(:one)
    enrollment = sequence.sequence_enrollments.create!(contact: contact, entity: @entity, status: 'active')
    
    initial_opened = step.opened_count
    
    delivery = SequenceEmailDelivery.create!(
      email_sequence: sequence,
      sequence_step: step,
      sequence_enrollment: enrollment,
      contact: contact,
      entity: @entity,
      status: 'delivered',
      ses_message_id: 'test-message-open-123'
    )
    
    # Simulate SES open event
    ses_event = {
      "Message" => {
        "eventType" => "Open",
        "mail" => {
          "messageId" => "test-message-open-123",
          "tags" => [
            { "name" => "type", "value" => "sequence" }
          ]
        },
        "open" => {
          "timestamp" => Time.current.iso8601
        }
      }.to_json
    }
    
    SesEventService.new.process_event(ses_event)
    
    delivery.reload
    step.reload
    
    assert_equal "opened", delivery.status
    assert_not_nil delivery.opened_at
    assert_equal initial_opened + 1, step.opened_count
  end

  test "SES event: bounce cancels enrollment and marks contact" do
    sequence = email_sequences(:active_sequence)
    step = sequence.sequence_steps.first || sequence.sequence_steps.create!(step_number: 1, delay_hours: 0, subject: "Test", body: "Test")
    contact = contacts(:one)
    contact.update!(opted_out: false)
    enrollment = sequence.sequence_enrollments.create!(contact: contact, entity: @entity, status: 'active')
    
    delivery = SequenceEmailDelivery.create!(
      email_sequence: sequence,
      sequence_step: step,
      sequence_enrollment: enrollment,
      contact: contact,
      entity: @entity,
      status: 'sent',
      ses_message_id: 'test-message-bounce-123'
    )
    
    # Simulate SES bounce event
    ses_event = {
      "Message" => {
        "eventType" => "Bounce",
        "mail" => {
          "messageId" => "test-message-bounce-123",
          "tags" => [
            { "name" => "type", "value" => "sequence" }
          ]
        },
        "bounce" => {
          "bounceType" => "Permanent",
          "bounceSubType" => "General"
        }
      }.to_json
    }
    
    SesEventService.new.process_event(ses_event)
    
    delivery.reload
    enrollment.reload
    contact.reload
    
    assert_equal "bounced", delivery.status
    assert_equal "cancelled", enrollment.status
    assert contact.opted_out?
  end

  private

  def api_headers
    { 
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end
end
