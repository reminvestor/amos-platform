# frozen_string_literal: true

# Sends push notifications to Hub thread participants when a new message arrives
class SendHubMessagePushNotificationsJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    return unless SnsPushNotificationService.configured?

    message = HubMessage.find_by(id: message_id)
    return unless message

    thread = message.hub_thread
    return unless thread

    # Get all user participants except the sender
    recipients = thread.user_participants.reject do |user|
      # Don't notify the sender
      message.sender_type == "User" && message.sender_id == user.id
    end

    return if recipients.empty?

    # Build notification content
    title = build_title(message, thread)
    body = build_body(message)
    data = build_data(message, thread)

    # Send to each recipient
    service = SnsPushNotificationService.new

    recipients.each do |user|
      # Skip if user is currently active in the thread (has recent presence)
      next if user_active_in_thread?(user, thread)

      # Get unread count for badge
      unread_count = calculate_unread_count(user, thread)

      begin
        service.send_to_user(
          user,
          title: title,
          body: body,
          data: data,
          badge: unread_count
        )
      rescue => e
        Rails.logger.error "[Push] Failed to notify user #{user.id}: #{e.message}"
      end
    end
  end

  private

  def build_title(message, thread)
    case thread.thread_type
    when HubThread::DM
      message.sender_name
    when HubThread::CHANNEL
      "##{thread.name}"
    when HubThread::GROUP
      thread.name || "Group Chat"
    else
      "New Message"
    end
  end

  def build_body(message)
    # Truncate long messages
    content = message.content.to_s.strip

    # For agent messages, add indicator
    prefix = message.from_agent? ? "🤖 " : ""

    # Handle different message types
    case message.message_type
    when HubMessage::FILE_SHARE
      "#{prefix}Shared a file"
    when HubMessage::GIF
      "#{prefix}Sent a GIF"
    when HubMessage::QUESTION
      "#{prefix}#{content.truncate(100)}"
    else
      "#{prefix}#{content.truncate(150)}"
    end
  end

  def build_data(message, thread)
    {
      type: "hub_message",
      thread_id: thread.id.to_s,
      thread_type: thread.thread_type,
      message_id: message.id.to_s,
      sender_id: message.sender_id.to_s,
      sender_type: message.sender_type
    }
  end

  def user_active_in_thread?(user, thread)
    # Check if user has recent presence (within last 30 seconds)
    presence = user.hub_presence
    return false unless presence&.status == "online"
    return false unless presence.current_thread_id == thread.id

    presence.last_activity_at && presence.last_activity_at > 30.seconds.ago
  end

  def calculate_unread_count(user, thread)
    # Get total unread across all threads for this user
    HubParticipant.where(
      participant: user,
      participant_type: "User"
    ).sum(:unread_count)
  end
end
