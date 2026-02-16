# frozen_string_literal: true

# AmosSignal - Real-time signals that can trigger AMOS autonomous responses
#
# Signals are the "senses" of the autonomous loop. They represent events
# that AMOS should be aware of and potentially act on.
#
# Signal lifecycle:
#   1. Event occurs (error, bounty change, integration failure, etc.)
#   2. Signal is recorded (with deduplication via fingerprint)
#   3. Signal monitor evaluates accumulated signals
#   4. If threshold met → triggers a reactive session
#   5. Session processes signal → marks as 'acted_on'
#
# Deduplication: Signals with the same fingerprint within a time window
# are counted (occurrence_count incremented) rather than creating duplicates.
#
class AmosSignal < ApplicationRecord
  belongs_to :entity

  SIGNAL_TYPES = %w[
    error_spike
    critical_ticket
    integration_failure_rate
    bounty_unclaimed_surge
    bounty_completed
    tool_failure_rate
    user_engagement_drop
    skill_effectiveness_drop
    resource_limit_warning
    anomaly_detected
    feature_demand
  ].freeze

  SOURCES = %w[
    support_ticket
    integration_log
    bounty
    agent_tool_execution
    resource_manager
    perception_service
    user_activity
    skill_injection_log
    error_log
  ].freeze

  STATUSES = %w[pending acknowledged acted_on dismissed expired].freeze

  validates :signal_type, inclusion: { in: SIGNAL_TYPES }
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :unprocessed, -> { where(status: %w[pending acknowledged]) }
  scope :recent, -> { order(created_at: :desc) }
  scope :strong, -> { where('strength >= ?', 0.7) }
  scope :by_strength, -> { order(strength: :desc) }

  # ═══════════════════════════════════════════════════════════════════════════
  # SIGNAL CREATION (with deduplication)
  # ═══════════════════════════════════════════════════════════════════════════

  # Record a signal, deduplicating within the window
  def self.record!(entity:, signal_type:, source:, strength:, summary:, data: {}, dedup_window: 30.minutes)
    fingerprint = generate_fingerprint(signal_type, source, data)

    # Check for existing signal within dedup window
    existing = where(entity: entity, fingerprint: fingerprint, status: %w[pending acknowledged])
                 .where('created_at > ?', dedup_window.ago)
                 .first

    if existing
      # Strengthen existing signal
      new_strength = [existing.strength + (strength * 0.2), 1.0].min
      existing.update!(
        occurrence_count: existing.occurrence_count + 1,
        strength: new_strength,
        data: existing.data.merge(
          'latest_occurrence' => Time.current.iso8601,
          'latest_data' => data
        )
      )
      existing
    else
      create!(
        entity: entity,
        signal_type: signal_type,
        source: source,
        strength: strength,
        summary: summary,
        data: data,
        fingerprint: fingerprint,
        first_seen_at: Time.current,
        status: 'pending'
      )
    end
  rescue => e
    Rails.logger.error "[AmosSignal] Failed to record signal: #{e.message}"
    nil
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # STATUS TRANSITIONS
  # ═══════════════════════════════════════════════════════════════════════════

  def acknowledge!
    update!(status: 'acknowledged', acknowledged_at: Time.current)
  end

  def mark_acted_on!(session_id: nil, thought_id: nil)
    update!(
      status: 'acted_on',
      acted_on_at: Time.current,
      thinking_session_id: session_id,
      working_memory_id: thought_id
    )
  end

  def dismiss!(reason: nil)
    update!(
      status: 'dismissed',
      data: data.merge('dismiss_reason' => reason)
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # EXPIRY
  # ═══════════════════════════════════════════════════════════════════════════

  def self.expire_old!(older_than: 24.hours)
    pending.where('created_at < ?', older_than.ago).update_all(status: 'expired')
  end

  private

  def self.generate_fingerprint(signal_type, source, data)
    # Create a stable fingerprint for deduplication
    # Use key identifying data, not timestamps or counts
    key_data = case signal_type
               when 'error_spike' then data.slice('error_class', 'error_pattern')
               when 'critical_ticket' then data.slice('ticket_id')
               when 'integration_failure_rate' then data.slice('integration_name')
               when 'tool_failure_rate' then data.slice('tool_name')
               when 'skill_effectiveness_drop' then data.slice('skill_id')
               else data.slice('key', 'id', 'name')
               end

    Digest::SHA256.hexdigest("#{signal_type}:#{source}:#{key_data.to_json}")[0..15]
  end
end
