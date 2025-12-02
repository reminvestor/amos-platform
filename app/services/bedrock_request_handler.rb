# Handles Bedrock requests with intelligent rate limiting and queueing
# Provides graceful UX when approaching AWS limits
class BedrockRequestHandler
  attr_reader :user, :entity, :task_session

  def initialize(user:, entity:, task_session: nil)
    @user = user
    @entity = entity
    @task_session = task_session
    @limiter = BedrockRateLimiter.new
  end

  # Send message with automatic rate limit handling
  # Returns: { success: true/false, response: string, queued: true/false, wait_time: seconds }
  def send_message(system_prompt, messages, **options, &block)
    # Check global rate limit
    permission = @limiter.acquire

    if permission[:allowed]
      # Under rate limit - send immediately (synchronous)
      send_immediate(system_prompt, messages, **options, &block)
    else
      # Over rate limit - decide based on urgency
      handle_rate_limited(system_prompt, messages, permission[:wait_time], **options)
    end
  end

  private

  def send_immediate(system_prompt, messages, **options, &block)
    bedrock = BedrockService.new(
      user: @user,
      entity: @entity,
      context: { task_session: @task_session }
    )

    if block_given?
      # Streaming response
      response = bedrock.send_message(system_prompt, messages, stream: true, **options, &block)
      { success: true, response: response, queued: false }
    else
      # Non-streaming response
      response = bedrock.send_message(system_prompt, messages, stream: false, **options)
      { success: true, response: response, queued: false }
    end

  rescue AmosErrors::BedrockThrottlingError => e
    # Still throttled despite rate limiting (AWS limit changed or race condition)
    Rails.logger.warn "Bedrock throttled despite rate limit check: #{e.message}"

    # Queue for retry
    queue_request(system_prompt, messages)
    {
      success: false,
      response: "⏱️ High demand right now - your message has been queued and will be processed in ~#{e.retry_after} seconds. You'll see the response shortly.",
      queued: true,
      wait_time: e.retry_after
    }
  end

  def handle_rate_limited(system_prompt, messages, wait_time, **options)
    # Check if wait time is short (< 10 seconds) - worth waiting synchronously
    if wait_time < 10
      Rails.logger.info "Rate limit hit, waiting #{wait_time}s before sending"

      # Wait and retry (user sees brief loading state)
      sleep(wait_time)
      send_immediate(system_prompt, messages, **options)
    else
      # Long wait - queue it and return immediately with friendly message
      Rails.logger.info "Rate limit hit, queueing request (#{wait_time}s wait)"

      queue_request(system_prompt, messages)
      {
        success: false,
        response: "⏱️ We're experiencing high demand right now. Your message has been queued and will be processed in approximately #{wait_time} seconds. You can continue chatting - I'll respond as soon as I can!",
        queued: true,
        wait_time: wait_time
      }
    end
  end

  def queue_request(system_prompt, messages)
    return unless @task_session

    # Queue for background processing
    QueuedBedrockRequestJob.set(wait: 5.seconds).perform_later(
      @task_session.id,
      messages.to_json,
      system_prompt
    )
  end
end
