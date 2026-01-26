# frozen_string_literal: true

module Admin
  # ExperienceLearningController - Admin dashboard for the continual learning system
  #
  # This controller provides visibility into:
  # - TaskExperiences (learned behaviors)
  # - Implicit feedback signals
  # - Confidence calibration
  # - Platform-wide experience promotion
  # - Conflict detection
  #
  class ExperienceLearningController < Admin::BaseController
    before_action :set_entity, only: [:entity, :experiences, :calibration]

    # GET /admin/experience_learning
    def index
      @entities = Entity.where(active: true).order(:name)

      # Global experience stats
      @global_stats = {
        total_experiences: TaskExperience.count,
        active_experiences: TaskExperience.active.count,
        platform_wide: TaskExperience.platform_wide.active.count,
        high_utility: TaskExperience.active.high_utility.count,
        by_source_type: TaskExperience.group(:source_type).count,
        avg_utility_score: TaskExperience.active.average(:utility_score)&.round(3),
        total_applications: TaskExperience.sum(:apply_count),
        avg_success_rate: calculate_avg_success_rate
      }

      # Task type breakdown
      @task_type_stats = TaskExperience.active
        .group(:task_type)
        .select('task_type, COUNT(*) as count, AVG(utility_score) as avg_utility, SUM(apply_count) as total_applications')
        .order('count DESC')

      # Recent experiences
      @recent_experiences = TaskExperience.includes(:entity)
        .order(created_at: :desc)
        .limit(20)

      # Top performing experiences
      @top_experiences = TaskExperience.active
        .high_utility
        .where('apply_count > ?', 5)
        .order(utility_score: :desc)
        .limit(10)

      # Recent learning activity
      @recent_cycles = EvolutionCycle.includes(:entity)
        .where("learnings::text LIKE '%experience_learning%'")
        .order(created_at: :desc)
        .limit(5)

      # Implicit feedback stats (last 7 days)
      @implicit_feedback_stats = calculate_implicit_feedback_stats

      # Confidence calibration overview
      @calibration_overview = calculate_calibration_overview
    end

    # GET /admin/experience_learning/entity/:entity_id
    def entity
      @experiences = TaskExperience.where(entity: @entity)
        .order(utility_score: :desc)
        .page(params[:page]).per(30)

      @entity_stats = {
        total: TaskExperience.where(entity: @entity).count,
        active: TaskExperience.where(entity: @entity).active.count,
        avg_utility: TaskExperience.where(entity: @entity).active.average(:utility_score)&.round(3),
        total_applications: TaskExperience.where(entity: @entity).sum(:apply_count),
        by_task_type: TaskExperience.where(entity: @entity).active.group(:task_type).count
      }

      # Conflicts detected
      @conflicts = detect_all_conflicts(@entity)

      # Calibration for this entity
      @calibration = Learning::ConfidenceCalibrationService.new(entity: @entity)
        .analyze_calibration(window: 30.days)
    end

    # GET /admin/experience_learning/experiences
    def experiences
      @experiences = TaskExperience.includes(:entity, :evolution_cycle)
        .order(created_at: :desc)

      # Filters
      @experiences = @experiences.where(entity_id: params[:entity_id]) if params[:entity_id].present?
      @experiences = @experiences.where(task_type: params[:task_type]) if params[:task_type].present?
      @experiences = @experiences.where(source_type: params[:source_type]) if params[:source_type].present?
      @experiences = @experiences.active if params[:active] == 'true'
      @experiences = @experiences.where('utility_score >= ?', 0.6) if params[:high_utility] == 'true'

      @experiences = @experiences.page(params[:page]).per(50)
    end

    # GET /admin/experience_learning/experience/:id
    def show_experience
      @experience = TaskExperience.find(params[:id])
      
      # Related decision traces (if we can find them)
      @related_traces = DecisionTrace.where(entity: @experience.entity)
        .where("metadata->>'task_type' = ?", @experience.task_type)
        .order(created_at: :desc)
        .limit(10)

      # Similar experiences
      @similar_experiences = TaskExperience.where(task_type: @experience.task_type)
        .where.not(id: @experience.id)
        .active
        .order(utility_score: :desc)
        .limit(5)
    end

    # GET /admin/experience_learning/calibration
    def calibration
      @service = Learning::ConfidenceCalibrationService.new(entity: @entity)
      @calibration = @service.analyze_calibration(window: params[:days]&.to_i&.days || 30.days)

      # Historical calibration (if we tracked it)
      @calibration_history = []

      # Decision trace sample for calibration analysis
      @sample_traces = DecisionTrace.where(entity: @entity)
        .where.not(confidence_score: nil)
        .where(outcome: %w[success failure])
        .order(created_at: :desc)
        .limit(50)
    end

    # GET /admin/experience_learning/platform_experiences
    def platform_experiences
      @platform_experiences = TaskExperience.platform_wide
        .active
        .order(utility_score: :desc)
        .page(params[:page]).per(30)

      @promotable = TaskExperience.where.not(entity_id: nil)
        .active
        .where('utility_score >= ?', 0.85)
        .where('apply_count >= ?', 15)
        .order(utility_score: :desc)
        .limit(20)
    end

    # GET /admin/experience_learning/conflicts
    def conflicts
      @all_conflicts = []

      Entity.where(active: true).find_each do |entity|
        TaskExperience::TASK_TYPES.each do |task_type|
          conflicts = TaskExperience.detect_conflicts(entity: entity, task_type: task_type)
          conflicts.each do |conflict|
            @all_conflicts << conflict.merge(entity: entity, task_type: task_type)
          end
        end
      end

      @all_conflicts.sort_by! { |c| -c[:experience_1][:success_rate].abs }
    end

    # GET /admin/experience_learning/implicit_feedback
    def implicit_feedback
      @stats = calculate_implicit_feedback_stats
      
      # Recent decision traces with implicit feedback
      @implicit_traces = DecisionTrace.where("outcome_details->>'source' = 'implicit_feedback'")
        .includes(:entity)
        .order(created_at: :desc)
        .page(params[:page]).per(50)
    end

    # POST /admin/experience_learning/run_maintenance
    def run_maintenance
      entity_id = params[:entity_id].presence

      if entity_id
        ExperienceMaintenanceJob.perform_later(entity_id: entity_id.to_i)
        redirect_to admin_experience_learning_entity_path(entity_id), 
          notice: 'Maintenance job queued for entity'
      else
        ExperienceMaintenanceJob.perform_later
        redirect_to admin_experience_learning_path, 
          notice: 'Global maintenance job queued'
      end
    end

    # POST /admin/experience_learning/promote/:id
    def promote
      experience = TaskExperience.find(params[:id])
      
      if experience.promotable_to_platform?
        promoted = TaskExperience.promote_to_platform!(experience)
        redirect_to admin_experience_learning_experience_path(promoted), 
          notice: 'Experience promoted to platform-wide'
      else
        redirect_back fallback_location: admin_experience_learning_path,
          alert: 'Experience not eligible for promotion'
      end
    end

    # POST /admin/experience_learning/deactivate/:id
    def deactivate
      experience = TaskExperience.find(params[:id])
      experience.deactivate!(reason: params[:reason] || 'admin_deactivation')
      
      redirect_back fallback_location: admin_experience_learning_path,
        notice: 'Experience deactivated'
    end

    # POST /admin/experience_learning/resolve_conflict
    def resolve_conflict
      entity = Entity.find(params[:entity_id])
      task_type = params[:task_type]

      resolved = TaskExperience.resolve_conflicts!(entity: entity, task_type: task_type)
      
      redirect_to admin_experience_learning_conflicts_path,
        notice: "#{resolved} conflict(s) resolved"
    end

    private

    def set_entity
      @entity = Entity.find(params[:entity_id])
    end

    def calculate_avg_success_rate
      experiences = TaskExperience.active.where('apply_count > 0')
      return 0 if experiences.empty?

      total_positive = experiences.sum(:positive_outcome_count)
      total_apply = experiences.sum(:apply_count)

      return 0.5 if total_apply.zero?
      (total_positive.to_f / total_apply).round(3)
    end

    def calculate_implicit_feedback_stats
      traces_7d = DecisionTrace.where('created_at > ?', 7.days.ago)
        .where("outcome_details->>'source' = 'implicit_feedback'")

      {
        total_7d: traces_7d.count,
        positive: traces_7d.where(outcome: 'success').count,
        negative: traces_7d.where(outcome: 'failure').count,
        detection_methods: traces_7d
          .where.not("outcome_details->>'detection_method'" => nil)
          .group("outcome_details->>'detection_method'")
          .count
      }
    end

    def calculate_calibration_overview
      # Get entities with enough data for calibration
      entities_with_data = []

      Entity.where(active: true).find_each do |entity|
        traces = DecisionTrace.where(entity: entity)
          .where.not(confidence_score: nil)
          .where(outcome: %w[success failure])
          .count

        next if traces < 20

        service = Learning::ConfidenceCalibrationService.new(entity: entity)
        result = service.analyze_calibration(window: 30.days)

        entities_with_data << {
          entity: entity,
          data_points: result[:data_points],
          calibration_score: result[:overall_calibration_score],
          significant_miscalibration: result[:guidance][:significant_miscalibration]
        }
      end

      entities_with_data.sort_by { |e| e[:calibration_score] || 0 }
    end

    def detect_all_conflicts(entity)
      conflicts = []

      TaskExperience::TASK_TYPES.each do |task_type|
        task_conflicts = TaskExperience.detect_conflicts(entity: entity, task_type: task_type)
        conflicts.concat(task_conflicts.map { |c| c.merge(task_type: task_type) })
      end

      conflicts
    end
  end
end
