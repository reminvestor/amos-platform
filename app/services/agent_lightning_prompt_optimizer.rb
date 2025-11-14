# Phase 6: Service to apply optimized prompts back to workflow templates
# This service retrieves optimized prompts from the Python training service
# and applies them to Rails workflow templates
class AgentLightningPromptOptimizer
  attr_reader :entity

  def initialize(entity)
    @entity = entity
  end

  # Phase 6: Apply optimized prompts from a training job to workflow templates
  def apply_optimizations(job_id)
    Rails.logger.info("🚀 Applying optimizations from training job #{job_id}")

    # Get optimized prompts from Python service
    begin
      result = PythonAgentLightningClient.get_optimized_prompts(job_id)
    rescue PythonAgentLightningClient::ServiceUnavailableError => e
      Rails.logger.error("Could not retrieve optimized prompts: #{e.message}")
      return {
        success: false,
        error: "Python service unavailable",
        applied_count: 0
      }
    rescue => e
      Rails.logger.error("Failed to retrieve optimized prompts: #{e.message}")
      return {
        success: false,
        error: e.message,
        applied_count: 0
      }
    end

    optimized_prompts = result['optimized_prompts'] || {}
    improvement = result['improvement_percentage'] || 0

    Rails.logger.info("📈 Training showed #{improvement}% improvement")

    # Apply optimizations to workflow templates
    applied_count = 0
    applied_templates = []

    optimized_prompts.each do |context_type, prompt_data|
      begin
        templates_updated = apply_to_workflow_templates(context_type, prompt_data)
        applied_count += templates_updated.count
        applied_templates.concat(templates_updated)

        Rails.logger.info("✅ Applied optimizations to #{templates_updated.count} templates for #{context_type}")
      rescue => e
        Rails.logger.error("Failed to apply optimizations for #{context_type}: #{e.message}")
      end
    end

    # Create optimization record for tracking
    begin
      optimization = AgentLightningOptimization.create!(
        entity: @entity,
        training_job_id: job_id,
        improvement_percentage: improvement.round(2),
        prompts_optimized: optimized_prompts.keys,
        before_prompts: {},  # Could be populated with previous versions
        after_prompts: optimized_prompts,
        applied_at: Time.current,
        templates_updated: applied_templates
      )

      Rails.logger.info("✅ Created optimization record #{optimization.id}")
    rescue => e
      Rails.logger.warn("Could not create optimization record: #{e.message}")
    end

    {
      success: true,
      improvement_percentage: improvement,
      applied_count: applied_count,
      templates_updated: applied_templates,
      optimization_id: optimization&.id
    }
  end

  # Phase 6: Rollback optimizations from a previous optimization record
  def rollback_optimization(optimization_id)
    optimization = AgentLightningOptimization.find(optimization_id)

    Rails.logger.info("🔄 Rolling back optimization #{optimization_id}")

    # Get previous prompts (if available)
    before_prompts = optimization.before_prompts || {}
    rollback_count = 0

    before_prompts.each do |context_type, prompt_data|
      begin
        rollback_to_workflow_templates(context_type, prompt_data)
        rollback_count += 1
      rescue => e
        Rails.logger.error("Failed to rollback #{context_type}: #{e.message}")
      end
    end

    optimization.update!(
      rolled_back_at: Time.current,
      rollback_count: rollback_count
    )

    {
      success: true,
      rollback_count: rollback_count
    }
  end

  private

  # Apply optimized prompts to all matching workflow templates
  def apply_to_workflow_templates(context_type, prompt_data)
    templates_updated = []

    # Map context type to workflow phase
    phase = map_context_to_phase(context_type)
    return templates_updated unless phase

    # Load all V2 workflow templates
    template_dir = Rails.root.join('app/workflow_templates')
    template_files = Dir.glob(template_dir.join('*_v2.yml'))

    template_files.each do |file|
      begin
        template_data = YAML.load_file(file)
        next unless template_data.is_a?(Hash)

        # Check if template has this phase
        next unless template_data['phases']&.key?(phase)

        # Save current version
        current_instructions = template_data['phases'][phase].dig('instructions') || {}

        # Apply optimization
        template_data['phases'][phase]['instructions'] = prompt_data['optimized']

        # Add metadata
        template_data['optimized_at'] = Time.current.iso8601
        template_data['improvement_score'] = prompt_data['improvement']

        # Save updated template
        File.write(file, YAML.dump(template_data))

        templates_updated << File.basename(file)

        Rails.logger.debug("✅ Updated #{File.basename(file)} - #{phase} phase")
      rescue => e
        Rails.logger.error("Failed to update #{file}: #{e.message}")
      end
    end

    templates_updated
  end

  # Rollback prompts to previous version
  def rollback_to_workflow_templates(context_type, prompt_data)
    phase = map_context_to_phase(context_type)
    return unless phase

    template_dir = Rails.root.join('app/workflow_templates')
    template_files = Dir.glob(template_dir.join('*_v2.yml'))

    template_files.each do |file|
      begin
        template_data = YAML.load_file(file)
        next unless template_data.is_a?(Hash)
        next unless template_data['phases']&.key?(phase)

        # Restore previous version
        template_data['phases'][phase]['instructions'] = prompt_data
        template_data['rolled_back_at'] = Time.current.iso8601

        File.write(file, YAML.dump(template_data))

        Rails.logger.debug("🔄 Rolled back #{File.basename(file)} - #{phase} phase")
      rescue => e
        Rails.logger.error("Failed to rollback #{file}: #{e.message}")
      end
    end
  end

  # Map Agent Lightning context types to workflow phases
  def map_context_to_phase(context_type)
    mapping = {
      'gather_context' => 'gather_context',
      'goal_execution' => 'execute_goal',
      'validation' => 'validate_result',
      'execute_goal' => 'execute_goal'
    }

    mapping[context_type.to_s]
  end
end
