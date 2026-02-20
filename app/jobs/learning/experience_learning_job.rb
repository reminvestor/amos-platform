# frozen_string_literal: true

module Learning
  # ExperienceLearningJob - Periodic experience extraction via Training-Free GRPO
  #
  # This job runs the semantic advantage extraction process to learn from
  # comparing successful vs failed task executions. It's the background
  # engine for our continual learning system.
  #
  # Schedule: Weekly (recommended) or can be triggered manually
  #
  # Integration:
  # - Uses SemanticAdvantageService for extraction
  # - Can run independently of EvolutionCycleService for more frequent learning
  # - Records results for monitoring
  #
  # Usage:
  #   # Manual trigger
  #   Learning::ExperienceLearningJob.perform_later(entity_id: 123)
  #
  #   # Or for all entities
  #   Learning::ExperienceLearningJob.perform_later
  #
  class ExperienceLearningJob < ApplicationJob
    queue_as :learning

    # Run for a specific entity or all entities
    def perform(entity_id: nil, window_days: 7, task_types: nil)
      if entity_id.present?
        run_for_entity(Entity.find(entity_id), window_days, task_types)
      else
        run_for_all_entities(window_days, task_types)
      end
    end

    private

    def run_for_entity(entity, window_days, task_types)
      Rails.logger.info "[ExperienceLearning] Starting for entity #{entity.id} (#{entity.name})"

      service = Learning::SemanticAdvantageService.new(entity: entity)
      
      results = service.extract_experiences(
        window: window_days.days,
        task_types: task_types
      )

      # Extract model routing insights alongside semantic advantages
      model_insights = service.extract_model_routing_insights(window: window_days.days)
      results[:model_routing_insights] = model_insights.size

      # Log summary
      log_results(entity, results)

      # Record metrics for monitoring
      record_metrics(entity, results)

      results
    rescue => e
      Rails.logger.error "[ExperienceLearning] Failed for entity #{entity.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      { error: e.message }
    end

    def run_for_all_entities(window_days, task_types)
      Rails.logger.info "[ExperienceLearning] Starting for all entities"

      # Get entities with recent activity
      active_entities = Entity.joins(:decision_traces)
                              .where('decision_traces.created_at > ?', window_days.days.ago)
                              .distinct
                              .limit(100) # Safety limit

      total_results = {
        entities_processed: 0,
        total_experiences_created: 0,
        total_experiences_modified: 0,
        errors: []
      }

      active_entities.each do |entity|
        result = run_for_entity(entity, window_days, task_types)
        
        if result[:error]
          total_results[:errors] << { entity_id: entity.id, error: result[:error] }
        else
          total_results[:entities_processed] += 1
          total_results[:total_experiences_created] += result[:experiences_created].to_i
          total_results[:total_experiences_modified] += result[:experiences_modified].to_i
        end
      end

      Rails.logger.info "[ExperienceLearning] Complete: #{total_results[:entities_processed]} entities, " \
                        "#{total_results[:total_experiences_created]} experiences created"

      total_results
    end

    def log_results(entity, results)
      Rails.logger.info "[ExperienceLearning] Entity #{entity.id} results:"
      Rails.logger.info "  - Task types analyzed: #{results[:task_types_analyzed].join(', ')}"
      Rails.logger.info "  - Experiences created: #{results[:experiences_created]}"
      Rails.logger.info "  - Experiences modified: #{results[:experiences_modified]}"
      Rails.logger.info "  - Experiences deleted: #{results[:experiences_deleted]}"
      
      if results[:errors].any?
        Rails.logger.warn "  - Errors: #{results[:errors].count}"
        results[:errors].each { |e| Rails.logger.warn "    - #{e[:task_type]}: #{e[:error]}" }
      end
    end

    def record_metrics(entity, results)
      # Record for monitoring/dashboards if metrics system exists
      return unless defined?(PlatformMetric)
      
      PlatformMetric.record(
        entity: entity,
        metric_type: 'experience_learning',
        value: results[:experiences_created],
        metadata: {
          task_types: results[:task_types_analyzed],
          modified: results[:experiences_modified],
          deleted: results[:experiences_deleted]
        }
      )
    rescue => e
      Rails.logger.warn "[ExperienceLearning] Failed to record metrics: #{e.message}"
    end
  end
end
