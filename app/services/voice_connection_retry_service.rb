# VoiceConnectionRetryService - Handle STT provider connection failures with intelligent retry logic
#
# Responsibilities:
# - Implement exponential backoff for connection retries
# - Circuit breaker pattern to prevent cascading failures
# - Track retry attempts and failures
# - Support provider switching strategy
#
# Usage:
#   service = VoiceConnectionRetryService.new(voice_session)
#   success = service.connect_with_retries("eleven_labs", elevenLabsCreds)
class VoiceConnectionRetryService
  INITIAL_BACKOFF_MS = 100  # Start with 100ms
  MAX_BACKOFF_MS = 5000     # Cap at 5 seconds
  MAX_RETRIES = 3           # Max retry attempts per provider
  CIRCUIT_BREAKER_THRESHOLD = 5  # Failures before circuit opens

  attr_reader :voice_session, :retry_count, :circuit_breaker_state

  def initialize(voice_session)
    @voice_session = voice_session
    @retry_count = 0
    @circuit_breaker_state = {}
    @health_service = VoiceProviderHealthService.new
  end

  # Attempt connection with retry logic and circuit breaker
  #
  # @param provider [String] Provider name ("eleven_labs" or "deepgram")
  # @param credentials [Hash] Provider credentials
  # @param block [Proc] Connection attempt block
  # @return [Boolean] Success/failure
  def connect_with_retries(provider, credentials, &block)
    @retry_count = 0

    # Check circuit breaker
    if circuit_breaker_open?(provider)
      log_circuit_breaker_open(provider)
      return false
    end

    loop do
      begin
        Rails.logger.info "🔄 Attempting #{provider} connection (attempt #{@retry_count + 1}/#{MAX_RETRIES + 1})"

        # Execute connection attempt
        result = block.call(credentials)

        # Success
        @health_service.record_successful_connection(provider, 0)
        reset_circuit_breaker(provider)
        log_success(provider)
        return true

      rescue => error
        @retry_count += 1
        @health_service.record_failed_connection(provider, error.message)

        if @retry_count > MAX_RETRIES
          # Max retries exceeded
          open_circuit_breaker(provider)
          log_max_retries_exceeded(provider, error)
          return false
        end

        # Calculate exponential backoff
        backoff_ms = calculate_backoff(@retry_count)

        log_retry_attempt(provider, error, @retry_count, backoff_ms)

        # Wait before retry
        sleep(backoff_ms.to_f / 1000)
      end
    end
  end

  # Intelligent provider selection with fallback
  #
  # @param primary_provider [String] Preferred provider
  # @param fallback_provider [String] Fallback provider
  # @param primary_creds [Hash] Primary provider credentials
  # @param fallback_creds [Hash] Fallback provider credentials
  # @param primary_block [Proc] Primary connection block
  # @param fallback_block [Proc] Fallback connection block
  # @return [Hash] { success: bool, provider: string, error: string }
  def connect_with_fallback(primary_provider, fallback_provider, primary_creds, fallback_creds, &block)
    Rails.logger.info "🚀 Attempting provider connection with fallback (#{primary_provider} → #{fallback_provider})"

    # Try primary provider
    primary_success = connect_with_retries(primary_provider, primary_creds) do |creds|
      block.call(primary_provider, creds)
    end

    if primary_success
      Rails.logger.info "✅ Connected via #{primary_provider}"
      return { success: true, provider: primary_provider }
    end

    # Primary failed, try fallback
    Rails.logger.warn "⚠️ #{primary_provider} failed, attempting #{fallback_provider} fallback"

    fallback_success = connect_with_retries(fallback_provider, fallback_creds) do |creds|
      block.call(fallback_provider, creds)
    end

    if fallback_success
      Rails.logger.info "✅ Connected via #{fallback_provider} (fallback)"
      return { success: true, provider: fallback_provider }
    end

    # Both failed
    Rails.logger.error "❌ Both #{primary_provider} and #{fallback_provider} failed"
    {
      success: false,
      provider: nil,
      error: "All STT providers unavailable"
    }
  end

  # Reset retry counter and circuit breaker after successful connection
  #
  # @param provider [String] Provider name
  def reset_on_success(provider)
    @retry_count = 0
    reset_circuit_breaker(provider)
  end

  # Get circuit breaker status
  #
  # @param provider [String] Provider name
  # @return [Boolean] True if circuit is open (provider unavailable)
  def circuit_breaker_open?(provider)
    state = Rails.cache.read("voice:circuit_breaker:#{provider}")
    state && state[:open] == true
  end

  # Get retry statistics
  #
  # @return [Hash] Statistics about retries
  def get_statistics
    {
      current_retry_count: @retry_count,
      providers_in_circuit: get_open_circuits,
      timestamp: Time.current
    }
  end

  private

  def calculate_backoff(attempt)
    # Exponential backoff with jitter
    base_backoff = INITIAL_BACKOFF_MS * (2 ** (attempt - 1))
    capped_backoff = [base_backoff, MAX_BACKOFF_MS].min

    # Add random jitter (±20%)
    jitter = rand(-20..20) / 100.0
    ((capped_backoff * (1 + jitter)).to_i).clamp(INITIAL_BACKOFF_MS, MAX_BACKOFF_MS)
  end

  def open_circuit_breaker(provider)
    state = {
      open: true,
      opened_at: Time.current,
      reason: "Max retries exceeded"
    }
    Rails.cache.write("voice:circuit_breaker:#{provider}", state, expires_in: 1.hour)
    Rails.logger.warn "🔌 Circuit breaker opened for #{provider}"
  end

  def reset_circuit_breaker(provider)
    Rails.cache.delete("voice:circuit_breaker:#{provider}")
    Rails.logger.info "🔌 Circuit breaker reset for #{provider}"
  end

  def get_open_circuits
    circuits = []
    ["eleven_labs", "deepgram"].each do |provider|
      circuits << provider if circuit_breaker_open?(provider)
    end
    circuits
  end

  def log_retry_attempt(provider, error, attempt, backoff_ms)
    Rails.logger.warn({
      event: "voice_connection_retry",
      provider: provider,
      attempt: attempt,
      error: error.message,
      backoff_ms: backoff_ms,
      voice_session_id: voice_session.session_id
    }.to_json)
  end

  def log_success(provider)
    Rails.logger.info({
      event: "voice_connection_success",
      provider: provider,
      attempts: @retry_count + 1,
      voice_session_id: voice_session.session_id
    }.to_json)
  end

  def log_max_retries_exceeded(provider, error)
    Rails.logger.error({
      event: "voice_connection_failed",
      provider: provider,
      reason: "Max retries exceeded",
      error: error.message,
      total_attempts: @retry_count,
      voice_session_id: voice_session.session_id
    }.to_json)
  end

  def log_circuit_breaker_open(provider)
    Rails.logger.warn({
      event: "voice_circuit_breaker_open",
      provider: provider,
      message: "Provider unavailable due to repeated failures",
      voice_session_id: voice_session.session_id
    }.to_json)
  end
end
