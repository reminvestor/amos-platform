# frozen_string_literal: true

module Admin
  class ContextGraphController < Admin::BaseController
    before_action :set_entity, only: [:entity, :decisions, :precedents, :exceptions]

    # GET /admin/context_graph
    def index
      @entities = Entity.all.order(:name)
      
      # Global stats
      @global_stats = {
        total_decisions: DecisionTrace.count,
        decisions_today: DecisionTrace.where('created_at > ?', 24.hours.ago).count,
        total_exceptions: DecisionTrace.exceptions.count,
        pending_approvals: DecisionTrace.where(approval_status: 'pending').count,
        total_precedent_links: DecisionPrecedent.count
      }

      # Recent decisions
      @recent_decisions = DecisionTrace.includes(:entity, :agent_plugin)
        .order(created_at: :desc)
        .limit(20)

      # Recent exceptions
      @recent_exceptions = DecisionTrace.exceptions
        .includes(:entity, :agent_plugin)
        .order(created_at: :desc)
        .limit(10)

      # Pending approvals
      @pending_approvals = DecisionTrace.where(approval_status: 'pending')
        .includes(:entity, :agent_plugin)
        .order(created_at: :desc)
        .limit(10)

      # Decision type breakdown (last 7 days)
      @decision_breakdown = DecisionTrace.where('created_at > ?', 7.days.ago)
        .group(:decision_type)
        .count
    end

    # GET /admin/context_graph/entity/:entity_id
    def entity
      @decisions = DecisionTrace.where(entity: @entity)
        .includes(:agent_plugin, :decision_precedents)
        .order(created_at: :desc)
        .page(params[:page]).per(30)

      @stats = calculate_entity_stats(@entity)
    end

    # GET /admin/context_graph/decisions
    def decisions
      @decisions = DecisionTrace.includes(:entity, :agent_plugin, :decision_precedents)
        .order(created_at: :desc)
        .page(params[:page]).per(50)

      # Filters
      @decisions = @decisions.where(entity: @entity) if @entity
      @decisions = @decisions.where(decision_type: params[:type]) if params[:type].present?
      @decisions = @decisions.where(outcome: params[:outcome]) if params[:outcome].present?
      @decisions = @decisions.exceptions if params[:exceptions] == 'true'
    end

    # GET /admin/context_graph/decision/:id
    def show_decision
      @decision = DecisionTrace.includes(:decision_precedents, :precedents, :child_decisions)
        .find(params[:id])
      @similar = @decision.find_similar_decisions(limit: 5)
    end

    # GET /admin/context_graph/precedents
    def precedents
      @precedent_links = DecisionPrecedent.includes(:decision_trace, :precedent_decision)
        .order(created_at: :desc)
        .page(params[:page]).per(50)

      @top_precedents = top_cited_precedents(limit: 20)
    end

    # GET /admin/context_graph/exceptions
    def exceptions
      @exceptions = DecisionTrace.exceptions
        .includes(:entity, :agent_plugin, :decision_precedents)
        .order(created_at: :desc)

      @exceptions = @exceptions.where(entity: @entity) if @entity
      @exceptions = @exceptions.page(params[:page]).per(30)

      @exception_stats = {
        total: DecisionTrace.exceptions.count,
        approved: DecisionTrace.exceptions.where(outcome: 'success').count,
        with_precedent: DecisionTrace.exceptions.with_precedents.count
      }
    end

    # GET /admin/context_graph/approvals
    def approvals
      @pending = DecisionTrace.where(approval_status: 'pending')
        .includes(:entity, :agent_plugin)
        .order(created_at: :desc)

      @recent_approved = DecisionTrace.where(approval_status: 'approved')
        .includes(:entity, :agent_plugin)
        .order(approved_at: :desc)
        .limit(20)

      @recent_rejected = DecisionTrace.where(approval_status: 'rejected')
        .includes(:entity, :agent_plugin)
        .order(approved_at: :desc)
        .limit(20)
    end

    # POST /admin/context_graph/approve/:id
    def approve
      decision = DecisionTrace.find(params[:id])
      decision.approve!(approved_by: current_admin.email, notes: params[:notes])
      
      redirect_to admin_context_graph_approvals_path, notice: "Decision approved"
    end

    # POST /admin/context_graph/reject/:id
    def reject
      decision = DecisionTrace.find(params[:id])
      decision.reject!(rejected_by: current_admin.email, notes: params[:notes])
      
      redirect_to admin_context_graph_approvals_path, notice: "Decision rejected"
    end

    # GET /admin/context_graph/stats
    def stats
      @period = (params[:days] || 30).to_i.days

      @stats = {
        total_decisions: DecisionTrace.where('created_at > ?', @period.ago).count,
        by_type: DecisionTrace.where('created_at > ?', @period.ago).group(:decision_type).count,
        by_outcome: DecisionTrace.where('created_at > ?', @period.ago).group(:outcome).count,
        exception_rate: calculate_exception_rate(@period),
        precedent_usage_rate: calculate_precedent_usage_rate(@period),
        avg_confidence: DecisionTrace.where('created_at > ?', @period.ago)
          .where.not(confidence_score: nil)
          .average(:confidence_score)&.round(3)
      }

      # Calculate daily stats from DecisionTrace directly
      @daily_stats = DecisionTrace.where('created_at > ?', @period.ago)
        .group("DATE(created_at)")
        .select("DATE(created_at) as stats_date, COUNT(*) as decision_count")
        .order("DATE(created_at)")
    end

    private

    def set_entity
      @entity = Entity.find(params[:entity_id]) if params[:entity_id].present?
    end

    def calculate_entity_stats(entity)
      decisions = DecisionTrace.where(entity: entity)
      
      {
        total: decisions.count,
        last_7_days: decisions.where('created_at > ?', 7.days.ago).count,
        exceptions: decisions.exceptions.count,
        with_precedents: decisions.with_precedents.count,
        pending_approvals: decisions.where(approval_status: 'pending').count,
        success_rate: calculate_success_rate(decisions),
        by_type: decisions.group(:decision_type).count
      }
    end

    def calculate_success_rate(decisions)
      with_outcome = decisions.where.not(outcome: nil)
      return 0 if with_outcome.count.zero?
      
      successful = with_outcome.where(outcome: 'success').count
      (successful.to_f / with_outcome.count * 100).round(1)
    end

    def calculate_exception_rate(period)
      total = DecisionTrace.where('created_at > ?', period.ago).count
      return 0 if total.zero?
      
      exceptions = DecisionTrace.exceptions.where('created_at > ?', period.ago).count
      (exceptions.to_f / total * 100).round(1)
    end

    def calculate_precedent_usage_rate(period)
      total = DecisionTrace.where('created_at > ?', period.ago).count
      return 0 if total.zero?
      
      with_precedents = DecisionTrace.with_precedents.where('created_at > ?', period.ago).count
      (with_precedents.to_f / total * 100).round(1)
    end

    def top_cited_precedents(limit:)
      DecisionPrecedent.group(:precedent_decision_id)
        .count
        .sort_by { |_, count| -count }
        .first(limit)
        .map do |id, count|
          decision = DecisionTrace.find_by(id: id)
          {
            decision: decision,
            times_cited: count,
            summary: decision&.decision_summary&.truncate(80)
          }
        end.compact
    end
  end
end

