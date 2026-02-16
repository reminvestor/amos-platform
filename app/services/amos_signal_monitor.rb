# frozen_string_literal: true

# AmosSignalMonitor - Event-driven trigger for AMOS autonomous sessions
#
# Sits between the signal emitters (callbacks, notifications) and the
# autonomous loop. Evaluates accumulated signals and decides:
#   1. Is there enough signal to warrant a thinking session?
#   2. Should it be a full autonomous session or a lightweight reactive one?
#   3. Are we within budget/throttle limits?
#
# Triggering logic:
#   - IMMEDIATE: Any signal with strength >= 0.9 (critical)
#   - THRESHOLD: Accumulated signal strength >= 2.0 within 1 hour
#   - PATTERN:   3+ signals of same type within 30 minutes
#   - SCHEDULED: Falls back to the normal cron-scheduled sessions
#
# Throttling:
#   - Max 1 reactive session per entity per 2 hours
#   - Max 6 reactive sessions per entity per 24 hours
#   - Critical signals bypass the 2-hour cooldown (but not 24h max)
#
class AmosSignalMonitor
  # Triggering thresholds
  IMMEDIATE_STRENGTH = 0.9          # Single signal strength that triggers immediately
  ACCUMULATED_THRESHOLD = 2.0       # Total signal strength needed for threshold trigger
  ACCUMULATION_WINDOW = 1.hour      # Window for accumulating signals
  PATTERN_COUNT = 3                 # Same-type signals needed for pattern trigger
  PATTERN_WINDOW = 30.minutes       # Window for pattern detection

  # Throttling
  COOLDOWN_PERIOD = 2.hours         # Min time between reactive sessions
  CRITICAL_COOLDOWN = 15.minutes    # Shorter cooldown for critical signals
  MAX_DAILY_SESSIONS = 6            # Max reactive sessions per entity per day
  MAX_DAILY_TOKENS = 100_000        # Max tokens spent on reactive sessions per day

  attr_reader :entity

  def initialize(entity)
    @entity = entity
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MAIN EVALUATION
  # Called after a new signal is recorded. Decides whether to trigger.
  # ═══════════════════════════════════════════════════════════════════════════

  def evaluate!
    return { triggered: false, reason: 'throttled_daily' } if daily_limit_reached?

    pending_signals = AmosSignal.where(entity: entity).pending.recent

    return { triggered: false, reason: 'no_signals' } if pending_signals.empty?

    # Check trigger conditions in order of urgency
    trigger = check_immediate_trigger(pending_signals) ||
              check_pattern_trigger(pending_signals) ||
              check_threshold_trigger(pending_signals)

    if trigger
      return { triggered: false, reason: 'cooldown' } if in_cooldown? && !trigger[:critical]

      # Fire the session
      fire_reactive_session!(trigger, pending_signals)
    else
      { triggered: false, reason: 'below_threshold',
        pending_count: pending_signals.count,
        total_strength: pending_signals.sum(:strength).round(2) }
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TRIGGER CONDITIONS
  # ═══════════════════════════════════════════════════════════════════════════

  private

  # Single high-strength signal (critical error, system down, etc.)
  def check_immediate_trigger(signals)
    critical = signals.where('strength >= ?', IMMEDIATE_STRENGTH).first
    return nil unless critical

    {
      type: :immediate,
      critical: true,
      reason: "Critical signal: #{critical.summary}",
      primary_signal: critical,
      strength: critical.strength
    }
  end

  # Same type of signal firing repeatedly (pattern = systematic issue)
  def check_pattern_trigger(signals)
    recent = signals.where('created_at > ?', PATTERN_WINDOW.ago)

    # Group by signal type and find patterns
    patterns = recent.group(:signal_type).count
    pattern_type = patterns.find { |_, count| count >= PATTERN_COUNT }

    return nil unless pattern_type

    type_name, count = pattern_type
    type_signals = recent.where(signal_type: type_name)

    {
      type: :pattern,
      critical: type_signals.any? { |s| s.strength >= 0.8 },
      reason: "Pattern detected: #{count} #{type_name} signals in #{PATTERN_WINDOW.inspect}",
      primary_signal: type_signals.by_strength.first,
      strength: type_signals.sum(:strength) / type_signals.count, # Average strength
      pattern_count: count,
      pattern_type: type_name
    }
  end

  # Accumulated signal strength exceeds threshold
  def check_threshold_trigger(signals)
    recent = signals.where('created_at > ?', ACCUMULATION_WINDOW.ago)
    total_strength = recent.sum(:strength)

    return nil unless total_strength >= ACCUMULATED_THRESHOLD

    {
      type: :threshold,
      critical: false,
      reason: "Accumulated signal strength: #{total_strength.round(2)} (threshold: #{ACCUMULATED_THRESHOLD})",
      primary_signal: recent.by_strength.first,
      strength: total_strength
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SESSION FIRING
  # ═══════════════════════════════════════════════════════════════════════════

  def fire_reactive_session!(trigger, pending_signals)
    Rails.logger.info "[AmosSignalMonitor] 🚨 Triggering reactive session for #{entity.name}: " \
                      "#{trigger[:type]} — #{trigger[:reason]}"

    # Acknowledge all pending signals
    pending_signals.update_all(status: 'acknowledged', acknowledged_at: Time.current)

    # Decide session type
    if trigger[:critical] || trigger[:type] == :immediate
      # Full autonomous session for critical issues
      AmosReactiveSessionJob.perform_later(
        entity_id: entity.id,
        trigger_type: trigger[:type].to_s,
        trigger_reason: trigger[:reason],
        signal_ids: pending_signals.pluck(:id),
        session_mode: 'full'
      )
    else
      # Lightweight targeted session for pattern/threshold triggers
      AmosReactiveSessionJob.perform_later(
        entity_id: entity.id,
        trigger_type: trigger[:type].to_s,
        trigger_reason: trigger[:reason],
        signal_ids: pending_signals.pluck(:id),
        session_mode: 'targeted'
      )
    end

    {
      triggered: true,
      trigger_type: trigger[:type],
      reason: trigger[:reason],
      critical: trigger[:critical],
      signals_processed: pending_signals.count
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # THROTTLING
  # ═══════════════════════════════════════════════════════════════════════════

  def in_cooldown?
    last_reactive = AmosThinkingSession.where(entity: entity, session_type: 'reactive')
                                        .order(created_at: :desc)
                                        .first

    return false unless last_reactive

    last_reactive.created_at > COOLDOWN_PERIOD.ago
  end

  def daily_limit_reached?
    today_count = AmosThinkingSession.where(entity: entity, session_type: 'reactive')
                                      .where('created_at > ?', 24.hours.ago)
                                      .count

    today_count >= MAX_DAILY_SESSIONS
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS — Called from signal emitters
  # ═══════════════════════════════════════════════════════════════════════════

  # Convenience method: record a signal AND evaluate in one call
  # Use this from callbacks and notifications
  def self.emit!(entity:, signal_type:, source:, strength:, summary:, data: {})
    signal = AmosSignal.record!(
      entity: entity,
      signal_type: signal_type,
      source: source,
      strength: strength,
      summary: summary,
      data: data
    )

    return unless signal

    # Evaluate asynchronously to not block the calling thread
    AmosSignalEvaluationJob.perform_later(entity_id: entity.id)

    signal
  end
end
