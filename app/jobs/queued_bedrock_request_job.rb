# Background job for processing Bedrock requests with rate limiting
# Queues requests when AWS is busy instead of showing users errors
class QueuedBedrockRequestJob < ApplicationJob
  queue_as :ai_requests

  # Retry on throttling with exponential backoff
  retry_on Aws::BedrockRuntime::Errors::ThrottlingException,
           wait: :exponentially_longer,
           attempts: 5

  def perform(task_session_id, messages_json, system_prompt)
    task_session = TaskSession.find(task_session_id)
    user = task_session.user
    entity = task_session.entity

    # Check rate limit before calling Bedrock
    limiter = BedrockRateLimiter.new
    permission = limiter.acquire

    unless permission[:allowed]
      # Reschedule for later instead of failing
      Rails.logger.info "Bedrock rate limit reached, rescheduling in #{permission[:wait_time]}s"
      self.class.set(wait: permission[:wait_time].seconds).perform_later(
        task_session_id,
        messages_json,
        system_prompt
      )
      return
    end

    # Process the request
    bedrock = BedrockService.new(
      user: user,
      entity: entity,
      context: { task_session: task_session }
    )

    messages = JSON.parse(messages_json, symbolize_names: true)
    response = bedrock.send_message(system_prompt, messages, stream: false)

    # Save response to task session
    scout_message = task_session.scout_messages.create!(
      role: "assistant",
      content: response,
      user: user
    )

    # Broadcast to user via Action Cable (real-time update)
    ActionCable.server.broadcast(
      "scout_#{task_session.session_id}",
      {
        type: "message",
        id: scout_message.id,
        content: response,
        queued: true,  # Let UI know this was queued
        timestamp: scout_message.created_at.iso8601
      }
    )

    Rails.logger.info "Queued Bedrock request completed for session #{task_session.session_id}"

  rescue AmosErrors::BedrockThrottlingError => e
    # Retry later if still throttled
    Rails.logger.warn "Bedrock throttled despite rate limiting, retrying in 30s"
    self.class.set(wait: 30.seconds).perform_later(task_session_id, message_content)
  end
end
