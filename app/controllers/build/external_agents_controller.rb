# frozen_string_literal: true

module Build
  class ExternalAgentsController < Build::BaseController
    before_action :require_authentication!
    before_action :set_agent, only: [:show, :suspend, :reactivate, :destroy, :configure_webhook]

    def index
      @agents = current_user.external_agent_registrations
                             .includes(:entity)
                             .order(created_at: :desc)

      @stats = {
        active_agents: @agents.select(&:active?).count,
        total_completed: @agents.sum(&:total_bounties_completed),
        total_earned: @agents.sum { |a| a.total_tokens_earned.to_f },
        pending_reviews: pending_review_count
      }
    end

    def show
      @executions = @agent.external_agent_executions
                          .includes(:bounty)
                          .order(created_at: :desc)
                          .limit(20)

      @daily_stats = @agent.external_agent_daily_stats
                           .order(stat_date: :desc)
                           .limit(14)
    end

    def register
      entity = current_user.entity || current_user.entities&.first
      unless entity
        redirect_to external_agents_path, alert: "You need an Amos account to register agents."
        return
      end

      service = ExternalAgentService.new(user: current_user, entity: entity)
      result = service.register_agent(
        agent_identifier: params[:agent_identifier],
        agent_name: params[:agent_name],
        agent_platform: params[:agent_platform] || 'custom',
        capabilities: build_capabilities_from_params,
        metadata: { registration_source: 'build_portal' }
      )

      if result[:success]
        agent = result[:agent]

        # Configure webhook if provided
        if params[:webhook_url].present?
          agent.configure_webhook!(
            url: params[:webhook_url],
            events: params[:webhook_events] || []
          )
        end

        # Store the key in flash so the user can see it once
        flash[:agent_api_key] = agent.api_key
        flash[:agent_name] = agent.agent_name
        redirect_to external_agents_path, notice: "Agent '#{agent.agent_name}' registered successfully!"
      else
        redirect_to external_agents_path, alert: "Registration failed: #{result[:error]}"
      end
    end

    def suspend
      @agent.suspend!(reason: params[:reason] || "Suspended by operator")
      redirect_to external_agents_path, notice: "Agent '#{@agent.agent_name}' suspended."
    end

    def reactivate
      @agent.activate!
      redirect_to external_agents_path, notice: "Agent '#{@agent.agent_name}' reactivated."
    end

    def destroy
      name = @agent.agent_name
      @agent.revoke!
      redirect_to external_agents_path, notice: "Agent '#{name}' has been revoked."
    end

    def configure_webhook
      if params[:webhook_url].present?
        @agent.configure_webhook!(
          url: params[:webhook_url],
          events: params[:webhook_events] || []
        )
        redirect_to external_agent_path(@agent), notice: "Webhook configured."
      else
        @agent.update!(webhook_url: nil, webhook_secret: nil, webhook_events: [])
        redirect_to external_agent_path(@agent), notice: "Webhook disabled."
      end
    end

    def reviews
      @pending_executions = ExternalAgentExecution
        .joins(:external_agent_registration)
        .where(external_agent_registrations: { operator_id: current_user.id })
        .where(awaiting_human_review: true)
        .includes(:bounty, :external_agent_registration)
        .order(submitted_at: :desc)
    end

    def approve_review
      execution = ExternalAgentExecution
        .joins(:external_agent_registration)
        .where(external_agent_registrations: { operator_id: current_user.id })
        .find(params[:id])

      result = execution.human_approve!(
        reviewer: current_user,
        notes: params[:notes],
        final_points: params[:final_points]&.to_i
      )

      if result[:success]
        redirect_to external_agents_reviews_path, notice: "Work approved! #{result[:tokens_awarded]} AMOS awarded."
      else
        redirect_to external_agents_reviews_path, alert: result[:error]
      end
    end

    def reject_review
      execution = ExternalAgentExecution
        .joins(:external_agent_registration)
        .where(external_agent_registrations: { operator_id: current_user.id })
        .find(params[:id])

      result = execution.human_reject!(
        reviewer: current_user,
        notes: params[:notes]
      )

      if result[:success]
        redirect_to external_agents_reviews_path, notice: "Work rejected. Feedback sent to agent."
      else
        redirect_to external_agents_reviews_path, alert: result[:error]
      end
    end

    private

    def require_authentication!
      unless current_user
        redirect_to new_user_session_path, alert: "Please sign in to manage your agents."
      end
    end

    def set_agent
      @agent = current_user.external_agent_registrations.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to external_agents_path, alert: "Agent not found."
    end

    def build_capabilities_from_params
      caps = {}
      (params[:capabilities] || []).each do |cap|
        caps[cap] = { 'description' => "Can work on #{cap} tasks", 'confidence' => 0.8 }
      end
      caps
    end

    def pending_review_count
      ExternalAgentExecution
        .joins(:external_agent_registration)
        .where(external_agent_registrations: { operator_id: current_user.id })
        .where(awaiting_human_review: true)
        .count
    rescue
      0
    end
  end
end
