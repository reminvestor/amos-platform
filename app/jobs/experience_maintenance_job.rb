# frozen_string_literal: true

# ExperienceMaintenanceJob - Periodic maintenance for the experience learning system
#
# This job runs daily (or on-demand) to perform maintenance tasks:
# 1. Temporal decay - reduce utility of stale experiences
# 2. Platform promotion - promote high-performing experiences to platform-wide
# 3. Conflict resolution - detect and resolve contradicting experiences
# 4. Confidence calibration - analyze and correct confidence miscalibration
# 5. Pruning - remove low-utility experiences
#
# Scheduled via solid_queue or similar
#
class ExperienceMaintenanceJob < ApplicationJob
  queue_as :maintenance

  # Don't retry on failure - will run again tomorrow
  discard_on StandardError do |job, error|
    Rails.logger.error "[ExperienceMaintenanceJob] Failed: #{error.message}"
    Rails.logger.error error.backtrace.first(10).join("\n")
  end

  def perform(entity_id: nil)
    if entity_id
      # Run for specific entity
      entity = Entity.find_by(id: entity_id)
      return unless entity

      run_maintenance_for_entity(entity)
    else
      # Run for all active entities
      run_global_maintenance
    end
  end

  private

  def run_global_maintenance
    Rails.logger.info "[ExperienceMaintenanceJob] Starting global maintenance"

    results = {
      entities_processed: 0,
      total_decayed: 0,
      total_promoted: 0,
      total_conflicts_resolved: 0,
      total_pruned: 0,
      started_at: Time.current
    }

    # Run temporal decay globally first
    results[:total_decayed] = TaskExperience.apply_temporal_decay_all!

    # Run platform promotion globally
    results[:total_promoted] = TaskExperience.run_platform_promotion!

    # Process each entity for entity-specific maintenance
    Entity.where(active: true).find_each do |entity|
      entity_results = run_maintenance_for_entity(entity)
      
      results[:entities_processed] += 1
      results[:total_conflicts_resolved] += entity_results[:conflicts_resolved]
      results[:total_pruned] += entity_results[:pruned]
    end

    results[:completed_at] = Time.current
    results[:duration_seconds] = (results[:completed_at] - results[:started_at]).round(2)

    Rails.logger.info "[ExperienceMaintenanceJob] Global maintenance complete: #{results.to_json}"

    results
  end

  def run_maintenance_for_entity(entity)
    Rails.logger.info "[ExperienceMaintenanceJob] Processing entity #{entity.id}"

    results = {
      entity_id: entity.id,
      conflicts_resolved: 0,
      pruned: 0,
      calibration_score: nil
    }

    # Resolve conflicts for each task type
    TaskExperience::TASK_TYPES.each do |task_type|
      resolved = TaskExperience.resolve_conflicts!(entity: entity, task_type: task_type)
      results[:conflicts_resolved] += resolved
    end

    # Prune low-utility experiences
    results[:pruned] = TaskExperience.prune_low_utility!(entity: entity, keep_count: 50)

    # Run confidence calibration
    begin
      calibration_service = Learning::ConfidenceCalibrationService.new(entity: entity)
      calibration_result = calibration_service.analyze_calibration(window: 30.days)
      results[:calibration_score] = calibration_result[:overall_calibration_score]
    rescue => e
      Rails.logger.warn "[ExperienceMaintenanceJob] Calibration failed for entity #{entity.id}: #{e.message}"
    end

    # Merge similar experiences
    TaskExperience::TASK_TYPES.each do |task_type|
      TaskExperience.merge_similar!(entity: entity, task_type: task_type)
    end

    Rails.logger.info "[ExperienceMaintenanceJob] Entity #{entity.id} complete: " \
                      "#{results[:conflicts_resolved]} conflicts resolved, #{results[:pruned]} pruned"

    results
  end
end
