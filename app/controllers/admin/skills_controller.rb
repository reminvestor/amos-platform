# frozen_string_literal: true

module Admin
  class SkillsController < Admin::BaseController
    before_action :set_skill, only: [:show, :edit, :update, :destroy, :revert]

    # GET /admin/skills
    def index
      @skills = SystemSkill.order(:skill_type, :name)
      @skills = @skills.where(skill_type: params[:type]) if params[:type].present?
      @skills = @skills.where(status: params[:status]) if params[:status].present?
      @skills = @skills.where('name ILIKE ?', "%#{params[:search]}%") if params[:search].present?

      @stats = {
        total: SystemSkill.count,
        active: SystemSkill.active.count,
        integration: SystemSkill.integration_skills.count,
        task: SystemSkill.task_skills.count,
        custom: SystemSkill.custom_skills.count,
        evolved: SystemSkill.where('version > 1').count,
        avg_effectiveness: SystemSkill.where.not(effectiveness_score: nil).average(:effectiveness_score)&.round(1)
      }
    end

    # GET /admin/skills/:id
    def show
      @revisions = @skill.skill_revisions.order(version: :desc).limit(20)
      @recent_injections = @skill.skill_injection_logs.order(created_at: :desc).limit(20)

      @injection_stats = {
        total: @skill.injection_count,
        positive: @skill.positive_outcomes,
        negative: @skill.negative_outcomes,
        effectiveness: @skill.effectiveness_score,
        last_7_days: @skill.skill_injection_logs.where('created_at > ?', 7.days.ago).count
      }
    end

    # GET /admin/skills/:id/edit
    def edit; end

    # PATCH /admin/skills/:id
    def update
      old_content = @skill.content
      new_content = params[:system_skill][:content]

      if new_content.present? && new_content != old_content
        @skill.evolve!(
          new_content,
          source: 'admin',
          reason: params[:change_reason].presence || 'Manual admin edit',
          author: current_user
        )
        redirect_to admin_skill_path(@skill), notice: "Skill updated (v#{@skill.version})"
      elsif @skill.update(skill_params.except(:content))
        redirect_to admin_skill_path(@skill), notice: "Skill settings updated"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /admin/skills/:id
    def destroy
      @skill.update!(status: 'archived')
      redirect_to admin_skills_path, notice: "Skill '#{@skill.name}' archived"
    end

    # POST /admin/skills/:id/revert
    def revert
      target_version = params[:version].to_i
      @skill.revert_to!(target_version)
      redirect_to admin_skill_path(@skill), notice: "Reverted to version #{target_version}"
    rescue => e
      redirect_to admin_skill_path(@skill), alert: "Revert failed: #{e.message}"
    end

    # POST /admin/skills/evolve_now
    def evolve_now
      entity = Entity.first
      service = SkillEvolutionService.new(entity)
      results = service.evolve_skills!

      redirect_to admin_skills_path,
                  notice: "Evolution complete: #{results[:skills_evolved]} evolved, #{results[:proposals].count} proposals"
    rescue => e
      redirect_to admin_skills_path, alert: "Evolution failed: #{e.message}"
    end

    private

    def set_skill
      @skill = SystemSkill.find(params[:id])
    end

    def skill_params
      params.require(:system_skill).permit(:name, :status, :content, :keywords, :skill_type)
    end
  end
end
