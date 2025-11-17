class RunAgentLightningTrainingJob < ApplicationJob
  queue_as :default

  # Run Agent Lightning training for an entity
  # This job should be scheduled periodically (e.g., daily) via clockwork
  def perform(entity_id = nil)
    if entity_id
      # Run training for specific entity
      entity = Entity.find(entity_id)
      run_training_for_entity(entity)
    else
      # Run training for all enabled entities
      Entity.joins(:agent_lightning_config)
        .where(agent_lightning_configs: { enabled: true })
        .find_each do |entity|
        run_training_for_entity(entity)
      end
    end
  end

  private

  def run_training_for_entity(entity)
    Rails.logger.info "🚀 Running Agent Lightning training for entity: #{entity.name}"

    service = AgentLightningTrainingService.new(entity)

    # Check if training should run
    unless service.config.should_retrain?
      Rails.logger.info "⏭️ Training not due for #{entity.name} yet"
      return
    end

    # Check if we have enough traces
    unless service.config.ready_for_training?
      Rails.logger.warn "⚠️ Not enough traces for training in #{entity.name}"
      return
    end

    # Execute training
    result = service.execute_training

    if result[:success]
      Rails.logger.info "✅ Training completed for #{entity.name}"
      Rails.logger.info "   Traces used: #{result[:traces_used]}"
      Rails.logger.info "   Improvement: #{result[:improvement]}%"
      Rails.logger.info "   Metrics: #{result[:metrics]}"

      # Send notification to entity admins
      notify_admins(entity, result)
    else
      Rails.logger.error "❌ Training failed for #{entity.name}: #{result[:error]}"
    end

    result
  end

  def notify_admins(entity, training_result)
    # TODO: Send email/notification to entity admins about training results
    # Could integrate with existing notification system
  end
end
