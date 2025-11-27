# frozen_string_literal: true

module Dashboard
  class EnergyController < ApplicationController
    before_action :authenticate_user!
    before_action :set_entity

    def index
      @agents = AgentPlugin.where(entity: @entity)
        .includes(:energy_state, :capability_beliefs)
        .order(:name)

      @community_pool = CommunityEnergyPool.for_entity(@entity)

      @school_enrollments = AgentSchoolEnrollment
        .where(entity: @entity)
        .includes(:agent_plugin, :student_agent)
        .order(created_at: :desc)
        .limit(10)

      @recent_transactions = AgentEnergyTransaction
        .where(entity: @entity)
        .includes(:agent_plugin)
        .order(created_at: :desc)
        .limit(50)

      @ab_tests = AgentAbTest
        .where(entity: @entity)
        .includes(:control_agent, :variant_agent)
        .order(created_at: :desc)
        .limit(10)

      # Calculate summary stats
      @stats = calculate_stats
    end

    def show
      @agent = AgentPlugin.find(params[:id])
      authorize_agent!

      @energy_state = @agent.energy_state
      @capability_beliefs = @agent.capability_beliefs.order(avg_quality: :desc)
      @decision_boundary = @agent.decision_boundary

      @transactions = AgentEnergyTransaction
        .where(agent_plugin: @agent)
        .order(created_at: :desc)
        .limit(100)

      @collaborations_made = @agent.collaboration_requests_made
        .includes(:helper_agent)
        .order(created_at: :desc)
        .limit(20)

      @collaborations_received = @agent.collaboration_requests_received
        .includes(:requesting_agent)
        .order(created_at: :desc)
        .limit(20)

      @relationships = AgentRelationship
        .where('requester_id = ? OR helper_id = ?', @agent.id, @agent.id)
        .includes(:requester, :helper)
        .order(compatibility_score: :desc)

      @school_history = @agent.school_enrollments.order(created_at: :desc)
    end

    def regenerate
      EnergyRegenerationJob.perform_later
      redirect_to dashboard_energy_index_path, notice: 'Energy regeneration job queued'
    end

    def distribute_pool
      pool = CommunityEnergyPool.for_entity(@entity)
      result = pool.distribute!

      if result
        redirect_to dashboard_energy_index_path, notice: "Distributed #{result[:distributed].round(1)} energy to #{result[:recipients]} agents"
      else
        redirect_to dashboard_energy_index_path, alert: 'No distribution needed or possible'
      end
    end

    def enroll_in_school
      @agent = AgentPlugin.find(params[:id])
      authorize_agent!

      school = Collaboration::AgentSchool.new
      result = school.enroll(@agent)

      if result[:success]
        redirect_to dashboard_energy_path(@agent), notice: 'Agent enrolled in school'
      else
        redirect_to dashboard_energy_path(@agent), alert: "Enrollment failed: #{result[:error]}"
      end
    end

    private

    def set_entity
      @entity = current_user.entity
    end

    def authorize_agent!
      unless @agent.entity == @entity || current_user.admin?
        redirect_to dashboard_energy_index_path, alert: 'Access denied'
      end
    end

    def calculate_stats
      agents = AgentPlugin.where(entity: @entity).includes(:energy_state)

      energy_states = agents.filter_map(&:energy_state)

      {
        total_agents: agents.count,
        agents_with_energy: energy_states.count,
        total_energy: energy_states.sum(&:current_energy).round(1),
        avg_energy: energy_states.any? ? (energy_states.sum(&:current_energy) / energy_states.count).round(1) : 0,
        in_debt: energy_states.count(&:in_debt?),
        in_school: agents.in_school.count,
        on_probation: agents.on_probation.count,
        total_tasks_completed: energy_states.sum(&:tasks_completed),
        total_tasks_failed: energy_states.sum(&:tasks_failed),
        avg_success_rate: energy_states.any? ? (energy_states.sum(&:success_rate) / energy_states.count * 100).round(1) : 0,
        total_collaborations: energy_states.sum(&:help_given) + energy_states.sum(&:help_received)
      }
    end
  end
end

