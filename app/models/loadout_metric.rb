# frozen_string_literal: true

# LoadoutMetric - Tracks performance metrics for loadouts (plugin injections)
#
# Event types:
# - success: Loadout interaction completed successfully
# - failure: Loadout interaction failed
# - hallucination: AI claimed to do something without calling a tool
# - tool_call: A tool was called (success or failure tracked in details)
# - tool_error: A tool call failed
#
class LoadoutMetric < ApplicationRecord
  belongs_to :entity
  belongs_to :user, optional: true

  EVENTS = %w[success failure hallucination tool_call tool_error].freeze

  validates :loadout_slug, presence: true
  validates :event_type, presence: true, inclusion: { in: EVENTS }

  scope :for_loadout, ->(slug) { where(loadout_slug: slug) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :for_canvas, ->(canvas) { where(canvas_context: canvas) }
  scope :successes, -> { where(event_type: 'success') }
  scope :failures, -> { where(event_type: 'failure') }
  scope :hallucinations, -> { where(event_type: 'hallucination') }
  scope :recent, ->(window = 7.days) { where('created_at > ?', window.ago) }

  def self.record_success(loadout_slug:, entity:, user: nil, canvas: nil, details: {}, quality: nil, response_time_ms: nil, session_id: nil)
    create!(loadout_slug: loadout_slug, entity: entity, user: user, canvas_context: canvas,
            event_type: 'success', details: details, quality_score: quality,
            response_time_ms: response_time_ms, session_id: session_id)
  end

  def self.record_failure(loadout_slug:, entity:, user: nil, canvas: nil, details: {}, session_id: nil)
    create!(loadout_slug: loadout_slug, entity: entity, user: user, canvas_context: canvas,
            event_type: 'failure', details: details, quality_score: 0.0, session_id: session_id)
  end

  def self.record_hallucination(loadout_slug:, entity:, user: nil, canvas: nil, details: {}, session_id: nil)
    create!(loadout_slug: loadout_slug, entity: entity, user: user, canvas_context: canvas,
            event_type: 'hallucination', details: details, quality_score: 0.0, session_id: session_id)
  end

  def self.health_summary(loadout_slug:, entity_id:, window: 7.days)
    metrics = for_loadout(loadout_slug).for_entity(entity_id).recent(window)
    total = metrics.where(event_type: %w[success failure]).count
    {
      loadout_slug: loadout_slug,
      success_rate: total > 0 ? (metrics.successes.count.to_f / total * 100).round(1) : nil,
      hallucination_rate: total > 0 ? (metrics.hallucinations.count.to_f / total * 100).round(1) : nil,
      avg_quality: metrics.where.not(quality_score: nil).average(:quality_score)&.round(2),
      total_interactions: metrics.count
    }
  end
end
