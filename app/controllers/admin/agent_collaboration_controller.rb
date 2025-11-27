# frozen_string_literal: true

module Admin
  class AgentCollaborationController < Admin::BaseController
    def dashboard
      # Overall stats
      @stats = calculate_overall_stats

      # Energy distribution
      @energy_distribution = calculate_energy_distribution

      # Recent activity
      @recent_transactions = AgentEnergyTransaction
        .includes(:agent_plugin, :entity)
        .order(created_at: :desc)
        .limit(20)

      @recent_collaborations = AgentCollaborationRequest
        .includes(:requesting_agent, :helper_agent, :entity)
        .order(created_at: :desc)
        .limit(20)

      # School status
      @active_enrollments = AgentSchoolEnrollment
        .active
        .includes(:agent_plugin, :student_agent, :entity)
        .order(created_at: :desc)

      @recent_graduations = AgentSchoolEnrollment
        .where(status: %w[graduated expelled probation])
        .includes(:agent_plugin, :entity)
        .order(completed_at: :desc)
        .limit(10)

      # A/B Tests
      @running_tests = AgentAbTest
        .running
        .includes(:control_agent, :variant_agent, :entity)

      # Community pools
      @community_pools = CommunityEnergyPool.includes(:entity).all

      # Agents by status
      @agents_by_status = AgentPlugin.group(:status).count
    end

    def agents
      @agents = AgentPlugin
        .includes(:energy_state, :entity, :capability_beliefs, :decision_boundary)
        .order(params[:sort] || 'name')

      # Filtering
      @agents = @agents.where(status: params[:status]) if params[:status].present?
      @agents = @agents.where(entity_id: params[:entity_id]) if params[:entity_id].present?

      if params[:energy_filter].present?
        case params[:energy_filter]
        when 'low'
          @agents = @agents.joins(:energy_state).where('agent_energy_states.current_energy < ?', 20)
        when 'debt'
          @agents = @agents.joins(:energy_state).where(agent_energy_states: { in_debt: true })
        when 'healthy'
          @agents = @agents.joins(:energy_state).where('agent_energy_states.current_energy >= ?', 50)
        end
      end

      @agents = @agents.page(params[:page]).per(25) if @agents.respond_to?(:page)

      @entities = Entity.all
    end

    def agent_detail
      @agent = AgentPlugin.includes(:energy_state, :capability_beliefs, :decision_boundary).find(params[:id])
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

    def school
      @active_enrollments = AgentSchoolEnrollment
        .active
        .includes(:agent_plugin, :student_agent, :entity)
        .order(created_at: :desc)

      @completed_enrollments = AgentSchoolEnrollment
        .completed
        .includes(:agent_plugin, :student_agent, :entity)
        .order(completed_at: :desc)
        .limit(50)

      @stats = {
        total_enrollments: AgentSchoolEnrollment.count,
        active: @active_enrollments.count,
        graduated: AgentSchoolEnrollment.where(outcome: 'success').count,
        expelled: AgentSchoolEnrollment.where(outcome: 'failure').count,
        probation: AgentSchoolEnrollment.where(outcome: 'irreplaceable_failure').count,
        avg_attempts: AgentSchoolEnrollment.average(:attempt_number)&.round(1) || 0
      }

      @stats[:graduation_rate] = @stats[:total_enrollments] > 0 ?
        (@stats[:graduated].to_f / @stats[:total_enrollments] * 100).round(1) : 0
    end

    def collaborations
      @collaborations = AgentCollaborationRequest
        .includes(:requesting_agent, :helper_agent, :entity)
        .order(created_at: :desc)

      @collaborations = @collaborations.where(status: params[:status]) if params[:status].present?
      @collaborations = @collaborations.where(request_type: params[:request_type]) if params[:request_type].present?
      @collaborations = @collaborations.where(entity_id: params[:entity_id]) if params[:entity_id].present?

      @collaborations = @collaborations.page(params[:page]).per(50) if @collaborations.respond_to?(:page)

      @stats = {
        total: AgentCollaborationRequest.count,
        completed: AgentCollaborationRequest.completed.count,
        helpful: AgentCollaborationRequest.where(was_helpful: true).count,
        by_type: AgentCollaborationRequest.group(:request_type).count,
        by_status: AgentCollaborationRequest.group(:status).count
      }

      @entities = Entity.all
    end

    def ab_tests
      @tests = AgentAbTest
        .includes(:control_agent, :variant_agent, :enrollment, :entity)
        .order(created_at: :desc)

      @tests = @tests.where(status: params[:status]) if params[:status].present?
      @tests = @tests.page(params[:page]).per(25) if @tests.respond_to?(:page)

      @stats = {
        total: AgentAbTest.count,
        running: AgentAbTest.running.count,
        completed: AgentAbTest.completed.count,
        variant_wins: AgentAbTest.where(winner: 'variant').count,
        control_wins: AgentAbTest.where(winner: 'control').count,
        ties: AgentAbTest.where(winner: 'tie').count
      }
    end

    def transactions
      @transactions = AgentEnergyTransaction
        .includes(:agent_plugin, :entity)
        .order(created_at: :desc)

      @transactions = @transactions.where(transaction_type: params[:type]) if params[:type].present?
      @transactions = @transactions.where(entity_id: params[:entity_id]) if params[:entity_id].present?
      @transactions = @transactions.where(agent_plugin_id: params[:agent_id]) if params[:agent_id].present?

      if params[:date_range].present?
        case params[:date_range]
        when '24h'
          @transactions = @transactions.where('created_at > ?', 24.hours.ago)
        when '7d'
          @transactions = @transactions.where('created_at > ?', 7.days.ago)
        when '30d'
          @transactions = @transactions.where('created_at > ?', 30.days.ago)
        end
      end

      @transactions = @transactions.page(params[:page]).per(100) if @transactions.respond_to?(:page)

      @stats = {
        total_earned: AgentEnergyTransaction.where('amount > 0').sum(:amount),
        total_spent: AgentEnergyTransaction.where('amount < 0').sum(:amount).abs,
        by_type: AgentEnergyTransaction.group(:transaction_type).sum(:amount)
      }

      @entities = Entity.all
      @agents = AgentPlugin.order(:name)
    end

    # Actions
    def regenerate_all
      EnergyRegenerationJob.perform_later
      redirect_to dashboard_admin_agent_collaboration_index_path, notice: 'Energy regeneration job queued'
    end

    def distribute_pools
      count = 0
      CommunityEnergyPool.find_each do |pool|
        result = pool.distribute!
        count += result[:recipients] if result
      end
      redirect_to dashboard_admin_agent_collaboration_index_path, notice: "Distributed energy to #{count} agents"
    end

    def enroll_agent
      agent = AgentPlugin.find(params[:id])
      school = Collaboration::AgentSchool.new
      result = school.enroll(agent)

      if result[:success]
        redirect_to school_admin_agent_collaboration_index_path, notice: "#{agent.name} enrolled in school"
      else
        redirect_to agents_admin_agent_collaboration_index_path, alert: "Enrollment failed: #{result[:error]}"
      end
    end

    def cancel_test
      test = AgentAbTest.find(params[:id])
      test.cancel!
      redirect_to ab_tests_admin_agent_collaboration_index_path, notice: 'Test cancelled'
    end

    def recalibrate_capabilities
      AgentCapabilityRecalibrationJob.perform_later
      redirect_to dashboard_admin_agent_collaboration_index_path, notice: 'Capability recalibration job queued'
    end

    def update_boundaries
      AgentDecisionBoundaryUpdateJob.perform_later
      redirect_to dashboard_admin_agent_collaboration_index_path, notice: 'Decision boundary update job queued'
    end

    private

    def calculate_overall_stats
      energy_states = AgentEnergyState.all

      {
        total_agents: AgentPlugin.count,
        agents_with_energy: energy_states.count,
        total_energy: energy_states.sum(:current_energy).round(1),
        avg_energy: energy_states.any? ? (energy_states.average(:current_energy) || 0).round(1) : 0,
        in_debt: energy_states.where(in_debt: true).count,
        in_school: AgentPlugin.in_school.count,
        on_probation: AgentPlugin.on_probation.count,
        total_tasks_completed: energy_states.sum(:tasks_completed),
        total_tasks_failed: energy_states.sum(:tasks_failed),
        avg_success_rate: energy_states.any? ? (energy_states.average(:success_rate) * 100).round(1) : 0,
        total_collaborations: AgentCollaborationRequest.count,
        active_tests: AgentAbTest.running.count,
        community_pool_total: CommunityEnergyPool.sum(:current_balance).round(1)
      }
    end

    def calculate_energy_distribution
      {
        healthy: AgentEnergyState.where('current_energy >= ?', 50).count,
        medium: AgentEnergyState.where('current_energy >= ? AND current_energy < ?', 20, 50).count,
        low: AgentEnergyState.where('current_energy >= ? AND current_energy < ?', 0, 20).count,
        debt: AgentEnergyState.where('current_energy < ?', 0).count
      }
    end
  end
end

