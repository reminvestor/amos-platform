# frozen_string_literal: true

# PlatformHealthScanJob - Periodic platform health scanner
#
# Runs the AmosChecks registry and emits AmosSignals for any findings.
# The signal system handles deduplication, thresholds, and reactive sessions.
#
# Schedule: every 30 minutes (configured in recurring.yml)
#
class PlatformHealthScanJob < ApplicationJob
  queue_as :living_platform

  def perform
    Rails.logger.info "[PlatformHealthScan] Starting scan..."

    findings = AmosChecks::Registry.run_health_checks
    signals_emitted = 0

    findings.each do |finding|
      entity = finding.entity_id ? Entity.find_by(id: finding.entity_id) : default_entity
      next unless entity

      AmosSignal.record!(
        entity: entity,
        signal_type: finding.signal_type,
        source: "platform_health_scanner",
        strength: finding.signal_strength,
        summary: finding.summary,
        data: finding.to_signal_data
      )
      signals_emitted += 1
    end

    Rails.logger.info "[PlatformHealthScan] Complete: #{findings.size} finding(s), #{signals_emitted} signal(s) emitted"
  rescue => e
    Rails.logger.error "[PlatformHealthScan] Failed: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
  end

  private

  def default_entity
    @default_entity ||= Entity.find_by(slug: "amos-labs") || Entity.first
  end
end
